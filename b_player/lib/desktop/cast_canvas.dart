import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
  int? _textureId;
  String _layoutKey = '';
  int _frameRate = 0;
  int _screens = 0;
  List<String> _screenIds = const [];
  List<Map<String, Object?>> _layout = const [];
  Map<String, Object?>? _style;
  Map<String, Object?>? _lyric;
  Map<String, Object?>? _tick;

  /// 每块屏的素材构图；只在设置对象变化时重发，走词/进度不碰它。
  List<Map<String, Object?>> _composition = const [];

  /// 画布（所有投放区并集）的总像素，镜像窗口的 UV 与输入映射都拿它换算。
  int _canvasWidth = 0;
  int _canvasHeight = 0;

  /// 设置页的画布预览：拿画布浏览器的 Flutter 纹理，只在设置页开着时收帧。
  bool _previewOn = false;

  /// 画布浏览器上交给 Flutter 的纹理；未投放或画布没起来时为空。
  int? get previewTextureId => _browserId == null ? null : _textureId;

  /// 画布逻辑像素尺寸（预览裁剪的坐标系）。
  Size get canvasSize => Size(_canvasWidth.toDouble(), _canvasHeight.toDouble());

  /// 某块在投屏在画布里的矩形（逻辑像素）；不在投返回 null。
  Rect? canvasRectOf(String screenId) {
    final i = _screenIds.indexOf(screenId);
    if (i < 0 || i >= _layout.length) return null;
    final l = _layout[i];
    double n(String k) => (l[k] as num?)?.toDouble() ?? 0;
    final w = n('w');
    final h = n('h');
    if (w <= 0 || h <= 0) return null;
    return Rect.fromLTWH(n('x'), n('y'), w, h);
  }

  /// 设置页进入/离开屏幕管理时开关预览收帧。
  Future<void> setPreview(bool on) async {
    if (_previewOn == on) return;
    _previewOn = on;
    await _applyPreview();
  }

  Future<void> _applyPreview() async {
    final id = _browserId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('setFlutterPreview', {'browserId': id, 'on': _previewOn});
    } catch (_) {
      // 浏览器刚被重建时通道里还没有它；重建后 ensure 会再补一次。
    }
  }

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
      _canvasWidth = width;
      _canvasHeight = height;
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
        // 命名 profile = 持久化上下文：cookie / localStorage / IndexedDB / HTTP 缓存
        // 都落盘到 <cache>/cast，重启后登录态和站点数据还在。
        'profileName': 'cast',
        'javascriptChannels': '{}',
        'canvasMode': true,
        'canvasWidth': width,
        'canvasHeight': height,
        'frameRate': s.frameRate,
        'presenters': presenters,
      });
      final id = result?['browserId'] as int?;
      final textureId = result?['textureId'] as int?;
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
      _textureId = textureId != null && textureId >= 0 ? textureId : null;
      _layoutKey = key;
      _frameRate = s.frameRate;
      _screens = shown;
      _screenIds = ids;
      _layout = layout;
      _installEvents();
      if (_previewOn) unawaited(_applyPreview());
      EnodeLog.i('cast', '画布浏览器已创建 browserId=$id 屏数=$shown 布局=${width}x$height 帧率=${s.frameRate}');
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

  /// 改渲染帧率。一块画布只有一个浏览器，帧率天然全局（OBS 的浏览器源同理，
  /// 不能按素材分开）；CEF 内部按这个上限回调 paint，超出的帧直接丢。
  Future<void> applyFrameRate(int fps) async {
    final id = _browserId;
    if (id == null || fps == _frameRate) return;
    try {
      await _channel.invokeMethod<void>('setFrameRate', {'browserId': id, 'fps': fps});
      _frameRate = fps;
    } catch (e) {
      // 浏览器刚被重建/销毁时通道里已经没有它；下一次 ensure 会带上新帧率。
      EnodeLog.d('cast', '设置帧率失败：$e');
    }
  }

  /// 每块屏的素材叠层：切屏/拖位置/改层级/换素材都走这里。
  Future<void> applyComposition(CastSettings s, List<CastMonitor> monitors) async {
    _composition = castWebScreens(s, monitors);
    await _compose();
  }

  /// 打开某网址素材的"交互窗口"：普通桌面窗口实时镜像该素材在画布上的区域，
  /// 鼠标/键盘按坐标反算注入同一个 CEF 实例——窗口里看到的、操作的就是投放出去
  /// 的画面（投放屏在远处人看不到时的遥控器）。返回 false 时 [lastError] 有原因。
  Future<bool> openMirror(CastMaterial material, CastSettings s, List<CastMonitor> monitors) async {
    final browserId = _browserId;
    if (browserId == null || _canvasWidth <= 0 || _canvasHeight <= 0) {
      lastError = l10n.castMirrorNeedsCasting;
      return false;
    }
    final rect = urlMirrorCanvasRect(s, _screenIds, _layout, material.id);
    if (rect == null) {
      lastError = l10n.castMirrorNeedsCasting;
      return false;
    }
    // 窗口大小跟素材宽高比走：宽撑到 1280，高不超过 900，再兜个最小尺寸。
    final ratio = rect.height / rect.width;
    final width = math.max(320, math.min(1280, rect.width).round());
    final height = math.max(240, math.min(900, (width * ratio).round()));
    final u0 = rect.left / _canvasWidth;
    final v0 = rect.top / _canvasHeight;
    final u1 = rect.right / _canvasWidth;
    final v1 = rect.bottom / _canvasHeight;
    try {
      await _channel.invokeMethod('openMirrorWindow', {
        'browserId': browserId,
        'key': material.id,
        'title': l10n.urlInteractWindowTitle(_mirrorDisplayName(material)),
        'width': width,
        'height': height,
        'u0': u0,
        'v0': v0,
        'u1': u1,
        'v1': v1,
        'canvasWidth': _canvasWidth,
        'canvasHeight': _canvasHeight,
      });
      EnodeLog.i('cast', '交互窗口已开 ${material.name} rect=${rect.left.round()},${rect.top.round()}'
          '${rect.width.round()}x${rect.height.round()}');
      return true;
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
      EnodeLog.w('cast', '交互窗口打开失败：${e.code} ${e.message}');
      return false;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  Future<void> _compose() async {
    if (_browserId == null || _composition.isEmpty) return;
    await _eval('window.enodeCanvas.compose(${jsonEncode(_composition)});');
  }

  Future<void> pushLyric(
    List<LyricLine> lines, {
    int durationMs = 0,
    bool hasTrack = false,
    bool idle = false,
  }) async {
    _lyric = castWebLyric(lines, durationMs: durationMs, hasTrack: hasTrack, idle: idle);
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
    _textureId = null;
    _layoutKey = '';
    _frameRate = 0;
    _screens = 0;
    _screenIds = const [];
    _layout = const [];
    _composition = const [];
    _canvasWidth = 0;
    _canvasHeight = 0;
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

/// 素材在画布上的像素矩形（镜像窗口的裁剪与输入映射基准），找不到可见投放项
/// 时返回 null。`screenIds` 与 `layout` 同序，layout 每项是 {x,y,w,h,k}（画布 px）；
/// 投放几何用百分比，与 screen.html 渲染用的是同一套换算。
Rect? urlMirrorCanvasRect(
  CastSettings s,
  List<String> screenIds,
  List<Map<String, Object?>> layout,
  String materialId,
) {
  for (var i = 0; i < screenIds.length && i < layout.length; i++) {
    for (final p in s.placementsOn(screenIds[i])) {
      if (p.materialId != materialId || !p.visible) continue;
      final x = numTry(layout[i]['x']) ?? 0;
      final y = numTry(layout[i]['y']) ?? 0;
      final w = numTry(layout[i]['w']) ?? 0;
      final h = numTry(layout[i]['h']) ?? 0;
      if (w <= 0 || h <= 0) continue;
      return Rect.fromLTWH(x + p.x * w, y + p.y * h, p.width * w, p.height * h);
    }
  }
  return null;
}

double? numTry(Object? v) => v is num ? v.toDouble() : null;

/// 镜像窗口标题里的名字：优先素材名，退回网址 host，再退回整条网址。
String _mirrorDisplayName(CastMaterial m) {
  final name = m.name.trim();
  if (name.isNotEmpty) return name;
  final host = Uri.tryParse(m.url.trim())?.host ?? '';
  return host.isNotEmpty ? host : m.url.trim();
}
