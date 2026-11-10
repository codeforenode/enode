import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';
import 'cast_web.dart';

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

  /// 勾选的屏 / 模式 / 分辨率变了才重建浏览器；只改样式不发新浏览器。
  /// 返回 false 表示这次起不来，调用方应退回旧通道。
  Future<bool> ensure(CastSettings s, List<CastMonitor> monitors) async {
    final tiles = <_Tile>[];
    final ids = <String>[];
    for (final t in s.activeTargets(monitors)) {
      final m = _monitorOf(monitors, t.monitorId);
      if (m == null) continue;
      tiles.add(_Tile(castWindowBounds(m, t), castDesignSize(m, t)));
      ids.add(t.monitorId);
    }
    if (tiles.isEmpty) {
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
        presenters.add({
          'x': t.rect.left.round(),
          'y': t.rect.top.round(),
          'w': w,
          'h': h,
          'u0': x / width,
          'v0': y / height,
          'u1': (x + w) / width,
          'v1': (y + h) / height,
        });
      }
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('createBrowser', {
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
      if (shown <= 0) {
        // 例如退回了软件渲染：画面没有原生 presenter 可显示，别开一块看不见的浏览器。
        await _dispose(id);
        lastError = l10n.castNoPresenter;
        return false;
      }
      _browserId = id;
      _layoutKey = key;
      _screens = shown;
      _screenIds = ids;
      _layout = layout;
      _installEvents();
      // 页面加载完会再整份重放；这里先排一次，页面已就绪时就不用等。
      unawaited(_eval('window.enodeCanvas.layout(${jsonEncode(layout)});'));
      return true;
    } catch (e) {
      lastError = '$e';
      await stop();
      return false;
    }
  }

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
  }) async {
    _lyric = castWebLyric(lines, title: title, artist: artist, seat: seat, durationMs: durationMs);
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
    if (_lyric != null) {
      p['lines'] = _lyric!['lines'];
      p['nowPlaying'] = _lyric!['nowPlaying'];
    }
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
}

class _Tile {
  _Tile(this.rect, this.design);
  final Rect rect;
  final Size design;
}
