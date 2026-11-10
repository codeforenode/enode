import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';
import 'cast_canvas.dart';
import 'cast_web.dart';
import 'cast_window_main.dart';

/// 该开哪些投放窗：启用 + 勾选 + 这次真扫到的屏，三者齐了才算数。
/// 抽成纯函数是为了能在测试里喂假屏验生命周期，不用真的开窗口。
List<String> castWindowPlan(CastSettings s, List<CastMonitor> monitors) {
  if (!s.enabled) return const [];
  return [for (final t in s.activeTargets(monitors)) t.monitorId];
}

/// 建窗时的初始 payload（子引擎起来后靠它决定落位和第一帧画面）。
Map<String, Object?> castWindowPayload({
  required String mainId,
  required CastMonitor monitor,
  required CastTarget target,
  required CastStyle style,
}) {
  final b = castWindowBounds(monitor, target);
  final d = castDesignSize(monitor, target);
  return {
    'tag': castWindowTag,
    'main': mainId,
    'monitorId': monitor.id,
    'name': monitor.name,
    'title': l10n.castWindowTitle(monitor.name),
    'locale': currentLocale.toLanguageTag(),
    'fullscreen': target.mode == CastMode.fullscreen,
    'bounds': [b.left, b.top, b.width, b.height],
    'design': [d.width, d.height],
    'style': style.toJson(),
  };
}

/// 样式/几何改动：每台屏的 bounds 不同，所以逐台推；style 是同一份。
Map<String, Object?> castStylePush({
  required CastMonitor monitor,
  required CastTarget target,
  required CastStyle style,
}) {
  final b = castWindowBounds(monitor, target);
  final d = castDesignSize(monitor, target);
  return {
    'bounds': [b.left, b.top, b.width, b.height],
    'design': [d.width, d.height],
    'fullscreen': target.mode == CastMode.fullscreen,
    'style': style.toJson(),
  };
}

/// 歌词整包：所有窗收到的是同一个串，所以文字与行号不可能对不上。
Map<String, Object?> castLyricPush({required List<LyricLine> lines, QueueItem? nowPlaying}) => {
      'lines': [
        for (final l in lines)
          [
            l.startMs,
            l.text,
            l.endMs,
            if (l.words.isNotEmpty)
              [
                for (final w in l.words) [w.startMs, w.endMs, w.text],
              ],
          ],
      ],
      'title': nowPlaying?.title,
      'artist': nowPlaying?.artist,
      'seat': nowPlaying?.seatLabel,
      'durationMs': nowPlaying?.durationMs ?? 0,
      'hasTrack': nowPlaying != null,
    };

/// 时钟锚点：推的是「此刻的绝对位置 + 当时的墙钟」，子引擎自己往前推，
/// 主 isolate 每秒纠偏一次——多屏画面因此天然同步，不需要逐帧 IPC。
Map<String, Object?> castTickPush({
  required int positionMs,
  required bool playing,
  int? wallMs,
}) =>
    {
      'positionMs': positionMs,
      'wallMs': wallMs ?? DateTime.now().millisecondsSinceEpoch,
      'playing': playing,
    };

/// 主 isolate 侧的投放窗管家：建窗 / 收窗 / 推样式 / 推歌词 / 推锚点。
/// 只由 [AppState] 的监听驱动，设置页不直接调它。
class CastWindows {
  CastWindows(this._state) {
    _state.addListener(_onApp);
    // Windows 走「一块 canvas + 原生 presenter」；ENODE_CAST_LEGACY=1 可退回
    // 一屏一引擎一窗，排查用。非 Windows 没有 CEF 与多窗能力，保持原路径。
    if (Platform.isWindows && Platform.environment['ENODE_CAST_LEGACY'] != '1') {
      _canvas = CastCanvas()..onPresenterMenu = _onPresenterMenu;
    }
  }

  final AppState _state;
  final _wins = <String, WindowController>{};
  final _ready = <String, Completer<void>>{};
  CastCanvas? _canvas;

  /// 画布这条路已经试过起不来：本次运行不再重试，交给一屏一窗通道。
  bool _canvasBroken = false;

  /// 每扇窗建起来时是全屏还是区域模式：换模式要重开窗，
  /// 因为无边框 / setFullScreen 在 Windows 后端是一次性样式，原地切不干净。
  final _modes = <String, CastMode>{};

  WindowController? _self;
  CastSettings? _seenCast;
  String _lyricSig = '';
  int _lastTickMs = 0;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;
  bool _cefWarmed = false;

  /// 建窗失败/掉窗的原因，设置页会原样显示出来（拒绝要带回可读的理由）。
  String? lastError;

  /// 真的在投的屏数：画布模式是 presenter 窗数；旧通道是建好但还没回报 castReady 的窗数。
  int get windowCount {
    final canvas = _canvas;
    if (canvas != null && canvas.active) return canvas.screenCount;
    return _wins.keys.where((k) => !_ready.containsKey(k)).length;
  }

  List<String> get windowMonitorIds => _wins.keys.toList();

  /// 投放屏右键菜单：关掉本屏，或从任意一屏关掉全部。
  void _onPresenterMenu(int index, int command) {
    if (command == CastCanvas.menuCloseAll) {
      unawaited(_state.closeCasting());
      return;
    }
    final ids = _canvas?.screenIds ?? const <String>[];
    if (index < 0 || index >= ids.length) return;
    unawaited(_state.closeCastScreen(ids[index]));
  }

  void _onApp() {
    if (_disposed) return;
    // 设置换了对象才要重算开窗名单；只是进度/歌词变了就只推内容。
    final changed = !identical(_seenCast, _state.cast);
    if (changed) {
      unawaited(_sync());
    } else {
      unawaited(_push());
    }
  }

  /// 串行建窗：两扇同时改窗口样式会把整个进程干崩（#49 实测段错误、无 WER 记录）。
  Future<void> _sync() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _applyOnce();
      } while (_again && !_disposed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _applyOnce() async {
    final s = _state.cast;
    _seenCast = s;
    final plan = castWindowPlan(s, _state.castMonitors);
    // 画布通道：一块纹理 + 每屏一个原生 presenter，不再建 Flutter 子引擎。
    final canvas = _canvas;
    if (canvas != null && !_canvasBroken) {
      if (plan.isEmpty) {
        await canvas.stop();
      } else if (await canvas.ensure(s, _state.castMonitors)) {
        await canvas.applyComposition(s, _state.castMonitors);
        await _push(forceLyric: true);
        return;
      } else {
        _canvasBroken = true;
        final err = canvas.lastError;
        if (err != null) lastError = l10n.castCanvasFallback(err);
      }
    }
    // CEF 运行时是进程一份：在主引擎里起来，子引擎那边再调只是幂等返回，
    // 省得 CefInitialize 落在某个投放窗的通道回调里。
    if (plan.isNotEmpty && !_cefWarmed) {
      _cefWarmed = true;
      await castWebInitialize();
    }
    for (final id in _wins.keys.where((k) => !plan.contains(k)).toList()) {
      await _destroy(id);
    }
    for (final id in plan) {
      if (_wins.containsKey(id)) {
        if (_modes[id] == s.targetFor(id).mode) {
          await _pushStyle(id);
        } else {
          await _destroy(id);
          await _create(id);
        }
      } else {
        await _create(id);
      }
    }
    await _push(forceLyric: true);
  }

  Future<void> _create(String monitorId) async {
    final monitor = _monitorOf(monitorId);
    if (monitor == null) return;
    final s = _state.cast;
    final target = s.targetFor(monitorId);
    final ack = Completer<void>();
    _ready[monitorId] = ack;
    try {
      final self = _self ??= await _currentEngineWithHandler();
      final controller = await WindowController.create(WindowConfiguration(
        arguments: jsonEncode(castWindowPayload(
          mainId: self.windowId,
          monitor: monitor,
          target: target,
          style: s.style,
        )),
        hiddenAtLaunch: true,
      ));
      _wins[monitorId] = controller;
      _modes[monitorId] = target.mode;
      await ack.future.timeout(const Duration(seconds: 12));
      lastError = null;
    } on TimeoutException {
      // 句柄留着：窗可能只是起得慢，摘了登记就再也收不掉它（退出时会剩一块黑屏）。
      _ready.remove(monitorId);
      lastError = l10n.castWindowTimeout(monitor.name);
    } catch (e) {
      _wins.remove(monitorId);
      _modes.remove(monitorId);
      _ready.remove(monitorId);
      lastError = l10n.castWindowCreateFailed(monitor.name, '$e');
    }
  }

  /// 主窗自己的 controller 只取一次；子窗的回报（castReady）靠它的 method handler 收。
  Future<WindowController> _currentEngineWithHandler() async {
    final c = await WindowController.fromCurrentEngine();
    await c.setWindowMethodHandler(_onSubCall);
    return c;
  }

  Future<Object?> _onSubCall(MethodCall call) async {
    final a = call.arguments;
    if (call.method == 'castNote') {
      // 网页投放起不来时子引擎把原因带回来自绘退回：画面不会空，但设置页要说清楚是为什么。
      if (a is Map) lastError = l10n.castWebFallback('${a['reason']}');
      return null;
    }
    if (call.method != 'castReady') return null;
    final id = a is Map ? a['monitorId'] as String? : null;
    if (id != null) _ready.remove(id)?.complete();
    return null;
  }

  Future<void> _destroy(String monitorId) async {
    final controller = _wins.remove(monitorId);
    _modes.remove(monitorId);
    _ready.remove(monitorId)?.complete();
    if (controller == null) return;
    try {
      await controller.invokeMethod('close');
    } catch (_) {
      // 窗已经被用户关了（Alt+F4）或插件通道已断，收尾本来就该是幂等的。
    }
  }

  Future<void> _pushStyle(String monitorId) async {
    if (_ready.containsKey(monitorId)) return; // 建窗 payload 里已经带了这份样式
    final monitor = _monitorOf(monitorId);
    if (monitor == null) return;
    final s = _state.cast;
    await _send(monitorId, 'style',
        castStylePush(monitor: monitor, target: s.targetFor(monitorId), style: s.style));
  }

  Future<void> _push({bool forceLyric = false}) async {
    // 还没回报 castReady 的窗先不推：那侧的方法处理器可能还没注册，
    // 推过去会当成「窗已掉」而误删登记，屏幕上就多出一扇没人管的窗。
    final canvas = _canvas;
    final useCanvas = canvas != null && canvas.active;
    final live = _wins.keys.where((k) => !_ready.containsKey(k)).toList();
    if (!useCanvas && live.isEmpty) return;
    final np = _state.nowPlaying;
    final lines = _state.lyricLines;
    // 语言也算签名：占位文案随界面语言，切语言要重推一次。
    final sig = '${np?.trackKey ?? '-'}|${lines.length}|${currentLocale.toLanguageTag()}';
    if (forceLyric || sig != _lyricSig) {
      _lyricSig = sig;
      if (useCanvas) {
        await canvas.pushLyric(
          lines,
          title: np?.title,
          artist: np?.artist,
          seat: np?.seatLabel,
          durationMs: np?.durationMs ?? 0,
          hasTrack: np != null,
        );
      } else {
        final payload = castLyricPush(lines: lines, nowPlaying: np);
        for (final id in live) {
          await _send(id, 'lyric', payload);
        }
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (forceLyric || now - _lastTickMs >= 900) {
      _lastTickMs = now;
      if (useCanvas) {
        await canvas.pushTick(
          positionMs: np?.positionMs ?? 0,
          wallMs: now,
          playing: _state.playing && np != null,
        );
      } else {
        final tick = castTickPush(positionMs: np?.positionMs ?? 0, playing: _state.playing && np != null);
        for (final id in live) {
          await _send(id, 'tick', tick);
        }
      }
    }
  }

  Future<void> _send(String monitorId, String method, Object? args) async {
    final controller = _wins[monitorId];
    if (controller == null) return;
    try {
      await controller.invokeMethod(method, args);
    } catch (e) {
      // 子窗没了（Alt+F4 / 引擎被回收）：摘掉登记，等用户下次改设置再重建，别在这里反复开窗。
      _wins.remove(monitorId);
      _modes.remove(monitorId);
      final name = _monitorOf(monitorId)?.name ?? monitorId;
      lastError = l10n.castWindowGone(name, '$e');
    }
  }

  CastMonitor? _monitorOf(String id) {
    for (final m in _state.castMonitors) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 收起所有投放窗（托盘退出 / 关进程前调用）。
  Future<void> closeAll() async {
    await _canvas?.stop();
    for (final id in _wins.keys.toList()) {
      await _destroy(id);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state.removeListener(_onApp);
    unawaited(closeAll());
  }
}
