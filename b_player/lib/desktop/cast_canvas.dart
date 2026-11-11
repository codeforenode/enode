import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../log.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';
import 'cast_web.dart';
import 'monitor_rects.dart';

/// Windows 投放的新通道：一块 canvas 纹理 + 每块屏一个原生 presenter 窗。
///
/// 画面仍是 assets/cast/lyric.html：canvas.html 在「所有投放区的并集」尺寸里给
/// 每块屏摆一份完整构图（iframe），Dart 只推一份 payload，各屏由同一份数据渲染，
/// 同帧是结构上的保证，不靠逐帧对齐。CEF / 画布起不来时由 [CastWindows] 退回
/// 原来的「一屏一引擎一窗」，再不行还有 Flutter 自绘。
class CastCanvas {
  static const _channel = MethodChannel('flutter_chromium_webview');

  /// 原生菜单命令，和 canvas_presenter.h 里的 kMenuClose* 一一对应。
  static const menuCloseScreen = 1;
  static const menuCloseAll = 2;

  int? _browserId;
  String _layoutKey = '';
  int _screens = 0;
  List<String> _screenIds = const [];
  List<Map<String, Object?>> _layout = const [];
  Map<String, Object?>? _style;
  Map<String, Object?>? _lyric;
  Map<String, Object?>? _tick;

  /// 每块屏的素材构图；只在设置对象变化时重发，走词/进度不碰它。
  List<Map<String, Object?>> _composition = const [];

  /// 投放屏右键菜单：index 是 presenter 序号，command 见 menuClose*。
  void Function(int index, int command)? onPresenterMenu;

  bool get active => _browserId != null;

  /// 真正在投的屏数（presenter 窗数）。
  int get screenCount => _screens;

  /// 和 presenter 序号同序的屏幕 id。
  List<String> get screenIds => _screenIds;

  /// 最近一次失败原因；设置页原样显示。
  String? lastError;

  /// 画布通道在本次运行内已不可恢复（运行时被 shutdown，一进程只能初始化一次）。
  /// 置位后调用方不再因设置变更而重试画布，固定走一屏一窗，避免重试风暴。
  bool get dead => _dead;
  bool _dead = false;

  /// 勾选的屏 / 模式 / 分辨率变了才重建浏览器；只改样式不发新浏览器。
  /// 返回 false 表示这次起不来，调用方应退回旧通道。
  Future<bool> ensure(CastSettings s, List<CastMonitor> monitors) async {
    // 物理矩形问 user32 拿（rcMonitor/rcWork），拿不到就回退「逻辑 × 缩放」。
    // presenter 的 CreateWindowExW 吃物理像素，直接用逻辑坐标会在任何非 100%
    // 缩放的屏上投错位置；rcMonitor 顺带把「任务栏在顶部的屏全屏偏移」也修了。
    final physical = physicalMonitorRects();
    final tiles = <_Tile>[];
    final ids = <String>[];
    for (final t in s.activeTargets(monitors)) {
      final m = _monitorOf(monitors, t.monitorId);
      if (m == null) continue;
      tiles.add(_Tile(castWindowBounds(m, t), castDesignSize(m, t), _physicalRect(m, t, physical)));
      ids.add(t.monitorId);
    }
    if (tiles.isEmpty) {
      if (active) EnodeLog.i('cast', '投放计划为空，停画布并释放浏览器（CEF 运行时保留）');
      await stop();
      return false;
    }
    final key = [
      for (final t in tiles)
        '${t.rect.left.round()},${t.rect.top.round()},'
            '${t.rect.width.round()}x${t.rect.height.round()}',
    ].join('|');
    if (active && key == _layoutKey) {
      _screens = tiles.length;
      _screenIds = ids;
      return true;
    }
    await stop();
    lastError = null;

    final initOk = await castWebInitialize();
    if (!initOk) {
      lastError = l10n.castRuntimeMissing;
      return false;
    }
    try {
      // 画布纹理与页面布局用逻辑像素（与设置页预览同一套单位），
      // presenter 窗口用物理像素：UV 是比值，两套单位不串味。
      final union = tiles.map((t) => t.rect).reduce((a, b) => a.expandToInclude(b));
      final width = union.width.round();
      final height = union.height.round();
      if (width <= 0 || height <= 0) {
        lastError = l10n.castRegionZero;
        return false;
      }
      final layout = <Map<String, Object?>>[];
      final presenters = <Map<String, Object?>>[];
      for (final t in tiles) {
        final x = (t.rect.left - union.left).round();
        final y = (t.rect.top - union.top).round();
        final w = t.rect.width.round();
        final h = t.rect.height.round();
        layout.add({'x': x, 'y': y, 'w': w, 'h': h, 'k': castScaleFor(t.design)});
        final p = t.physical;
        presenters.add({
          'x': p.left.round(),
          'y': p.top.round(),
          'w': p.width.round(),
          'h': p.height.round(),
          'u0': x / width,
          'v0': y / height,
          'u1': (x + w) / width,
          'v1': (y + h) / height,
        });
      }
      final result = await _createBrowser({
        'initialUrl': castCanvasPageUrl(),
        'mediaPlaybackRequiresUserGesture': false,
        // 不传 profileName：CEF 用一个新的内存上下文，画布不落盘任何数据。
        'javascriptChannels': '{}',
        'canvasMode': true,
        'canvasWidth': width,
        'canvasHeight': height,
        'presenters': presenters,
      });
      final id = result?['browserId'] as int?;
      final shown = result?['presenters'] as int? ?? 0;
      if (id == null) {
        lastError = l10n.castNoBrowserHandle;
        return false;
      }
      if (shown != tiles.length) {
        // 0 = 没有任何 presenter（如退回软件渲染）；< tiles.length = 某块屏建窗/DX 失败。
        // presenter 序号与屏的对应关系一旦缺一环就错位（右键菜单会关错屏），
        // 画布是全有或全无：缺任何一块都整体放弃，交给一屏一窗通道逐屏兜底。
        await _dispose(id);
        lastError = l10n.castNoPresenter;
        EnodeLog.w('cast', '画布 presenter 不完整：建成 $shown/${tiles.length}，放弃画布');
        return false;
      }
      _browserId = id;
      _layoutKey = key;
      _screens = shown;
      _screenIds = ids;
      _layout = layout;
      _installEvents();
      EnodeLog.i('cast', '画布浏览器已创建 browserId=$id 屏数=$shown 布局=${width}x$height');
      // 页面加载完会再整份重放；这里先排一次，页面已就绪时就不用等。
      unawaited(_eval('window.enodeCanvas.layout(${jsonEncode(layout)});'));
      return true;
    } on PlatformException catch (e) {
      // NOT_READY：插件运行时不在 kReady（已被 shutdown 或仍在复位中）。
      // 绝不重试 initialize——那会把进程带崩；如实上报，让调用方本次退回一屏一窗。
      // shutdown 过的运行时在进程内不可恢复，标记 dead 让调用方别再重试。
      if (e.code == 'NOT_READY') {
        _dead = true;
        lastError = 'CEF 运行时未就绪（NOT_READY）：本次运行画布通道不可用';
      } else {
        lastError = '$e';
      }
      EnodeLog.w('cast', '画布 createBrowser 失败 code=${e.code}：${e.message}');
      await stop();
      return false;
    } catch (e) {
      lastError = '$e';
      await stop();
      return false;
    }
  }

  /// 建浏览器。**绝不在失败后重新初始化 CEF**：一个进程只能初始化一次，
  /// 第二次会 `INIT_FAILED` 并很快把进程带崩（0xc0000005）。
  /// NOT_READY 只说明插件那边的运行时已经不可用，交给调用方退回自绘即可。
  Future<Map<Object?, Object?>?> _createBrowser(Map<String, Object?> args) =>
      _channel.invokeMethod<Map<Object?, Object?>>('createBrowser', args);

  /// 旧接口：只更新歌词样式（回退/兼容用，画布主路径用 [applyComposition]）。
  Future<void> applyStyle(CastStyle style) async {
    _style = castWebStyle(style);
    await _push({'style': _style});
  }

  /// 每块屏的素材叠层：切屏/拖位置/改层级/换素材都走这里。
  Future<void> applyComposition(CastSettings s, List<CastMonitor> monitors) async {
    _composition = castWebScreens(s, monitors);
    await _compose();
  }

  Future<void> _compose() async {
    if (_browserId == null || _composition.isEmpty) return;
    await _eval('window.enodeCanvas.compose(${jsonEncode(_composition)});');
  }

  Future<void> pushLyric(
    List<LyricLine> lines, {
    String? title,
    String? artist,
    String? seat,
    int durationMs = 0,
    bool hasTrack = false,
    bool idle = false,
  }) async {
    _lyric = castWebLyric(
        lines,
        title: title,
        artist: artist,
        seat: seat,
        durationMs: durationMs,
        hasTrack: hasTrack,
        idle: idle);
    await _push(_lyric!);
  }

  Future<void> pushTick({required int positionMs, required int wallMs, required bool playing}) async {
    _tick = {
      'tick': {'positionMs': positionMs, 'wallMs': wallMs, 'playing': playing},
    };
    await _push(_tick!);
  }

  Future<void> stop() async {
    final id = _browserId;
    _browserId = null;
    _layoutKey = '';
    _screens = 0;
    _screenIds = const [];
    _layout = const [];
    _composition = const [];
    if (id == null) return;
    await _dispose(id);
    // 注意：这里**不**重新初始化 CEF。原生 disposeBrowser 只是从 browsers_ 表里
    // 摘掉浏览器句柄，运行时仍是 kReady，之后 createBrowser 直接可用——之前
    // 「会话被清空、必须重新初始化」是误判：一个进程二次 initialize() 必
    // INIT_FAILED，并很快把进程带崩（0xc0000005）。关了再开，靠的是复用
    // 已初始化的运行时重建浏览器，而不是重跑 initialize。
  }

  /// 页面每次导航（含重建）后 window.enode 都是新的，必须整份重推。
  void _installEvents() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onBrowserEvent') return null;
      final m = call.arguments;
      if (m is! Map) return null;
      if (m['browserId'] != _browserId) return null;
      final event = m['event'];
      if (event == 'presenterMenu') {
        final a = m['args'];
        if (a is Map) {
          final index = (a['index'] as num?)?.toInt() ?? -1;
          final command = (a['command'] as num?)?.toInt() ?? 0;
          onPresenterMenu?.call(index, command);
        }
        return null;
      }
      if (event != 'loadingStateChanged') return null;
      final a = m['args'];
      final loading = a is Map ? a['isLoading'] == true : true;
      if (!loading) unawaited(_replay());
      return null;
    });
  }

  Future<void> _replay() async {
    if (_browserId == null) return;
    await _eval('window.enodeCanvas.layout(${jsonEncode(_layout)});');
    await _compose();
    final p = <String, Object?>{};
    if (_style != null) p['style'] = _style;
    // 整份重发（含 noLyrics/idle/nowPlaying）：页面重载后 window.enode 归零，
    // 手工拆字段会把这些漏掉，闲时引导语和占位文案要等下一次歌词变化才回来。
    if (_lyric != null) p.addAll(_lyric!);
    if (_tick != null) p['tick'] = _tick!['tick'];
    if (p.isNotEmpty) await _eval('window.enodeCanvas.push(${jsonEncode(p)});');
  }

  Future<void> _push(Map<String, Object?> sections) async {
    if (_browserId == null) return;
    await _eval('window.enodeCanvas.push(${jsonEncode(sections)});');
  }

  Future<void> _eval(String js) async {
    final id = _browserId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('executeJavaScript', {'browserId': id, 'js': js});
    } catch (_) {
      // 页面/浏览器已经没了：等下一次 ensure 重建，推送失败不该把设置页弄成错误状态。
    }
  }

  Future<void> _dispose(int id) async {
    try {
      await _channel.invokeMethod<void>('disposeBrowser', {'browserId': id});
    } catch (_) {
      // 已经关掉或通道已断，收尾是幂等的。
    }
  }

  static CastMonitor? _monitorOf(List<CastMonitor> monitors, String id) {
    for (final m in monitors) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 该投放区在桌面上的**物理像素**矩形（给 presenter 窗口用）。
  ///
  /// 优先用 user32 的 rcMonitor/rcWork 精确值（顺带修「任务栏在顶部的屏全屏偏移」）；
  /// 匹配不上就退回「逻辑矩形 × 该屏缩放」——screen_retriever 的逻辑坐标本来就是
  /// 物理坐标除以缩放，乘回去在取整误差内是准的。
  static Rect _physicalRect(
      CastMonitor m, CastTarget t, List<PhysicalMonitorRects> physical) {
    final logical = castWindowBounds(m, t);
    final predictedWork = Rect.fromLTWH(
        m.workOrigin.dx * m.scale, m.workOrigin.dy * m.scale, m.workSize.width * m.scale, m.workSize.height * m.scale);
    final match = matchPhysicalRect(predictedWork: predictedWork, all: physical);
    if (match != null) {
      if (t.mode == CastMode.fullscreen) return match.monitor;
      return Rect.fromLTWH(
        match.work.left + t.region.left * match.work.width,
        match.work.top + t.region.top * match.work.height,
        t.region.width * match.work.width,
        t.region.height * match.work.height,
      );
    }
    return Rect.fromLTWH(logical.left * m.scale, logical.top * m.scale,
        logical.width * m.scale, logical.height * m.scale);
  }
}

class _Tile {
  _Tile(this.rect, this.design, this.physical);

  /// 画布/页面侧的逻辑像素矩形（与设置页预览同一套单位）。
  final Rect rect;

  /// 设计尺寸（逻辑像素），字号折算基准。
  final Size design;

  /// presenter 窗口的物理像素矩形。
  final Rect physical;
}
