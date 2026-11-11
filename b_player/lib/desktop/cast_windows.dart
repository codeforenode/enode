import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../log.dart';
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
Map<String, Object?> castLyricPush({
  required List<LyricLine> lines,
  QueueItem? nowPlaying,
  bool idle = false,
}) =>
    {
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
      // 没带桌号就给 null，投放页的 trim() 判断会自动跳过这一段。
      'seat': nowPlaying?.seat,
      'durationMs': nowPlaying?.durationMs ?? 0,
      'hasTrack': nowPlaying != null,
      // 闲时引导语的显隐开关：没有曲目、队列也空时才是 true。
      'idle': idle,
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
      // 画布失败一次就永久退化会很难受：店家改一下设置（换屏、拖位置）应该能再试。
      // 只在「用户确实改了配置」时重试，不会变成每 2 秒的循环。
      // 但 dead 是进程级不可恢复（运行时已 shutdown，重初始化必崩），
      // 这种情况下不再重试，本次运行固定一屏一窗。
      if (_canvasBroken && !(_canvas?.dead ?? false)) {
        _canvasBroken = false;
        EnodeLog.i('cast', '投放设置已变更，重新尝试画布通道');
      }
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
    // 快照一次用到底：await 中途拔插屏/重扫会换列表，布局与构图各读一版会闪一帧错位。
    final monitors = _state.castMonitors;
    final plan = castWindowPlan(s, monitors);
    EnodeLog.d(
      'cast',
      '应用投放计划：屏数=${plan.length} 通道=${_canvas != null && !_canvasBroken ? '画布' : '一屏一窗'}',
    );
    // 画布通道：一块纹理 + 每屏一个原生 presenter，不再建 Flutter 子引擎。
    final canvas = _canvas;
    if (canvas != null && !_canvasBroken) {
      if (plan.isEmpty) {
        await canvas.stop();
      } else if (await canvas.ensure(s, monitors)) {
        // 画布通了：把一屏一窗时代可能留下的子窗全部收掉。那些窗置顶、
        // 鼠标穿透、不可手动关，留着就是叠在新画面上的幽灵窗。
        if (_wins.isNotEmpty) {
          EnodeLog.i('cast', '画布恢复，收掉遗留的一屏一窗子窗 ${_wins.length} 扇');
          for (final id in _wins.keys.toList()) {
            await _destroy(id);
          }
        }
        await canvas.applyComposition(s, monitors);
        await _push(forceLyric: true);
        return;
      } else {
        _canvasBroken = true;
        final err = canvas.lastError;
        if (err != null) lastError = l10n.castCanvasFallback(err);
        EnodeLog.w('cast', '画布通道起不来，退回一屏一窗：${err ?? '原因未知'}');
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
      EnodeLog.i('cast', '投放窗就绪 ${monitor.name} mode=${target.mode.name}');
    } on TimeoutException {
      // 句柄留着：窗可能只是起得慢，摘了登记就再也收不掉它（退出时会剩一块黑屏）。
      _ready.remove(monitorId);
      lastError = l10n.castWindowTimeout(monitor.name);
      EnodeLog.w('cast', '投放窗 12s 没回报就绪 ${monitor.name}');
    } catch (e, st) {
      _wins.remove(monitorId);
      _modes.remove(monitorId);
      _ready.remove(monitorId);
      lastError = l10n.castWindowCreateFailed(monitor.name, '$e');
      EnodeLog.e('cast', '建投放窗失败 ${monitor.name}', e, st);
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
      if (a is Map) {
        lastError = l10n.castWebFallback('${a['reason']}');
        final detail = a['detail'];
        EnodeLog.w(
          'cast',
          '网页投放退回自绘 ${a['monitorId'] ?? ''}：${a['reason']}'
          '${detail == null ? '' : ' / $detail'}',
        );
      }
      return null;
    }
    if (call.method != 'castReady') return null;
    final id = a is Map ? a['monitorId'] as String? : null;
    if (id != null) {
      final ack = _ready.remove(id);
      if (ack != null) {
        ack.complete();
        return null;
      }
      // 迟到的就绪：这扇窗在建窗超时后又被摘出了计划（或按失败收掉了），
      // 主进程已经没有它的句柄，之后再也发不出 close。趁它自己找上门，
      // 在应答里让它就地销毁——否则又是一扇收不到指令、用户也关不掉的置顶幽灵窗。
      if (!_wins.containsKey(id)) {
        EnodeLog.w('cast', '投放窗就绪来得太迟 $id，让它就地关闭');
        return {'stale': true};
      }
    }
    return null;
  }

  /// 正在销毁的窗：`_push` 不受 `_sync` 串行保护，销毁进行中它可能还持有旧的
  /// live 名单，invoke 失败会被当成「窗掉了」误报到设置页。
  final _destroying = <String>{};

  Future<void> _destroy(String monitorId) async {
    _destroying.add(monitorId);
    try {
      final controller = _wins.remove(monitorId);
      _modes.remove(monitorId);
      _ready.remove(monitorId)?.complete();
      if (controller == null) return;
      EnodeLog.d('cast', '收投放窗 $monitorId');
      try {
        await controller.invokeMethod('close');
      } catch (e) {
        // 窗已经被用户关了（Alt+F4）或插件通道已断，收尾本来就该是幂等的。
        EnodeLog.d('cast', '收投放窗 $monitorId 时通道已断：$e');
      }
    } finally {
      _destroying.remove(monitorId);
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
    // 「闲时」= 没有曲目在播、队列也空着：刚开机、点的歌都播完了。
    // 中途换歌时队列非空，不会闪出引导语。
    final idle = np == null && _state.queue.isEmpty;
    // 语言也算签名：占位文案随界面语言，切语言要重推一次。idle 同理——
    // 队列一空就得让引导语出来，不能等下一次换歌。
    final sig = '${np?.trackKey ?? '-'}|${lines.length}|${currentLocale.toLanguageTag()}|$idle';
    if (forceLyric || sig != _lyricSig) {
      _lyricSig = sig;
      if (useCanvas) {
        await canvas.pushLyric(
          lines,
          title: np?.title,
          artist: np?.artist,
          seat: np?.seat,
          durationMs: np?.durationMs ?? 0,
          hasTrack: np != null,
          idle: idle,
        );
      } else {
        final payload = castLyricPush(lines: lines, nowPlaying: np, idle: idle);
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
    if (controller == null || _destroying.contains(monitorId)) return;
    try {
      await controller.invokeMethod(method, args);
    } catch (e) {
      if (_destroying.contains(monitorId)) return; // 是我们自己收的，不是掉了
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
    EnodeLog.i('cast', '停止投放：画布=${_canvas?.active == true} 子窗=${_wins.length}');
    try {
      await _canvas?.stop();
    } catch (e, st) {
      // CEF 收尾偶尔会抛（presenter 已经没了）。不能让它挡住后面的收窗。
      EnodeLog.e('cast', '停止画布失败', e, st);
    }
    for (final id in _wins.keys.toList()) {
      await _destroy(id);
    }
    EnodeLog.i('cast', '投放已全部停止');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state.removeListener(_onApp);
    unawaited(closeAll());
  }
}
