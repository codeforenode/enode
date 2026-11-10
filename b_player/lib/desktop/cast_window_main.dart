import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chromium_webview/flutter_chromium_webview.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/l10n.dart';
import '../state/cast_settings.dart';
import '../state/lrc.dart';
import '../ui/cast_lyric_view.dart';
import 'cast_web.dart';

/// 投放窗在子引擎里的 payload 标记；主 isolate 用它和 #49 台架的载荷分流。
const castWindowTag = 'lyric';

/// 子引擎入口：一屏一窗一引擎，这里只画歌词，不碰曲库 / MQTT / 播放。
/// 返回 false 表示这份 payload 不是投放窗的（是台架的），交给调用方另派。
Future<bool> castWindowMain(List<String> args) async {
  final p = _payloadOf(args);
  if (p == null) return false;
  WidgetsFlutterBinding.ensureInitialized();
  // 子引擎是独立 isolate，主引擎绑定的语言不会跟过来；按载荷里的标签重新绑定。
  final localeTag = p['locale'] as String? ?? '';
  if (localeTag.isNotEmpty) bindL10n(localeForTag(localeTag));
  final bounds = _rect(p['bounds']);
  final fullscreen = p['fullscreen'] == true;
  final model = CastWindowModel(
    design: _size(p['design']),
    style: p['style'] is Map ? CastStyle.fromJson(p['style'] as Map) : CastStyle.defaults,
    bounds: bounds,
    fullscreen: fullscreen,
  );
  final self = await WindowController.fromCurrentEngine();
  final toMain = WindowController.fromWindowId(p['main'] as String? ?? '');

  await windowManager.ensureInitialized();
  await _styleWindow(
    bounds,
    fullscreen: fullscreen,
    title: p['title'] as String? ?? l10n.castWindowTitle(p['name'] as String? ?? ''),
  );
  await self.setWindowMethodHandler((call) async {
    await model.handle(call.method, call.arguments);
    return null;
  });
  // 回报主 isolate「这扇起来了」，它才敢建下一扇：并发改窗口样式会把整个进程干崩（#49 实测段错误，无 WER）。
  await toMain.invokeMethod('castReady', {'monitorId': p['monitorId']});
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: CastWindowView(
        model: model,
        // 网页起不来的时候把原因带回主 isolate，设置页要能看见是哪里不对。
        onNote: (reason) => unawaited(toMain.invokeMethod('castNote', {
          'monitorId': p['monitorId'],
          'reason': reason,
        })),
      ),
    ),
  ));
  return true;
}

Map<String, Object?>? _payloadOf(List<String> args) {
  try {
    // 插件把 WindowConfiguration.arguments 原样放到 args[2]。
    final raw = args.length >= 3 ? args[2] : (args.length >= 2 ? args[1] : '');
    final m = jsonDecode(raw) as Map<String, Object?>;
    return m['tag'] == castWindowTag ? m : null;
  } catch (_) {
    return null;
  }
}

Rect _rect(Object? v) {
  final a = v is List ? v : const [0, 0, 1920, 1080];
  double at(int i) => i < a.length && a[i] is num ? (a[i] as num).toDouble() : 0;
  return Rect.fromLTWH(at(0), at(1), at(2), at(3));
}

Size _size(Object? v) {
  final a = v is List ? v : const [1920, 1080];
  double at(int i) => i < a.length && a[i] is num ? (a[i] as num).toDouble() : 0;
  return Size(at(0) <= 0 ? 1920 : at(0), at(1) <= 0 ? 1080 : at(1));
}

/// 窗口样式顺序照搬 #49 台架，每一步都踩过坑，改动前读完注释。
Future<void> _styleWindow(Rect bounds, {required bool fullscreen, required String title}) async {
  await windowManager.setTitle(title);
  // setFullScreen 的实现整段包在 if (!is_frameless_) 里：先 setAsFrameless 它就什么都不做了。
  // 所以全屏投放要让它自己去变无边框，区域模式才手动 frameless。
  if (!fullscreen) await windowManager.setAsFrameless();
  await windowManager.setResizable(false);
  // window_manager 0.5.2 的 Windows 后端没有 setMovable，调了会 MissingPluginException。
  await windowManager.setMinimizable(false);
  await windowManager.setMaximizable(false);
  await windowManager.setClosable(false);
  // setSkipTaskbar 直接用 taskbar_ 指针，而它只在 waitUntilReadyToShow 里创建；不先调 → 子引擎里必 segfault。
  await windowManager.waitUntilReadyToShow();
  await windowManager.setSkipTaskbar(true);
  await windowManager.setHasShadow(false);
  await windowManager.setBounds(bounds);
  // setFullScreen 用 MonitorFromWindow(..., DEFAULTTONEAREST) 决定盖哪块屏，必须先搬窗再调，
  // 否则两扇都会落到同一块屏。
  if (fullscreen) await windowManager.setFullScreen(true);
  await windowManager.setIgnoreMouseEvents(true);
  // 鼠标穿透只需要 WS_EX_TRANSPARENT；window_manager 顺带加的 WS_EX_LAYERED 会让 DWM 把这一窗
  // 的内容按错误尺寸合成——实测放进 CEF 后整幅画面被压到下半屏并在横向放大 1.6 倍（#60）。
  _dropLayeredFlag(title);
  await windowManager.show();
  // 置顶必须排在 setBounds / show 之后：这两个在 Windows 后端里都写死 SetWindowPos(HWND_TOP)，
  // 会把 WS_EX_TOPMOST 当场清掉（实测 ex-style 0x8 → 0x0）。
  await windowManager.setAlwaysOnTop(true);
}

const _gwlExStyle = -20;
const _wsExLayered = 0x00080000;

/// 清掉 WS_EX_LAYERED，只留穿透位。窗口标题唯一定位到自己这一扇（标题里带显示器名）。
void _dropLayeredFlag(String title) {
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindow = user32.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
  final getLong = user32.lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
      'GetWindowLongPtrW');
  final setLong = user32.lookupFunction<IntPtr Function(IntPtr, Int32, IntPtr), int Function(int, int, int)>(
      'SetWindowLongPtrW');
  final name = title.toNativeUtf16();
  try {
    final hwnd = findWindow(nullptr, name);
    if (hwnd == 0) return;
    final ex = getLong(hwnd, _gwlExStyle);
    if (ex & _wsExLayered != 0) setLong(hwnd, _gwlExStyle, ex & ~_wsExLayered);
  } finally {
    malloc.free(name);
  }
}

/// 一扇投放窗的状态：样式与几何由主 isolate 推，进度靠「绝对锚点 + 本地墙钟」自己算。
/// 所有窗共用同一份歌词与同一个锚点，所以画面天然同步，不需要逐帧 IPC。
class CastWindowModel extends ChangeNotifier {
  CastWindowModel({
    required this.design,
    required this.style,
    required this.bounds,
    required this.fullscreen,
  });

  Size design;
  CastStyle style;
  Rect bounds;
  bool fullscreen;
  List<LyricLine> lines = const [];
  String? title;
  String? artist;
  String? seat;
  int durationMs = 0;

  int _anchorPos = 0;
  int _anchorWall = 0;
  bool _playing = false;
  Timer? _tick;

  /// 样式 / 歌词 / 锚点各自计数：投放网页只推变化的那一段，其余留在页面里不动。
  int styleRev = 0;
  int lyricRev = 0;
  int tickRev = 0;

  /// 推给页面的锚点：绝对进度 + 取样时的墙钟，页面自己按墙钟外推。
  int get anchorPositionMs => _anchorPos;
  int get anchorWallMs => _anchorWall;
  bool get playing => _playing;

  /// 当前进度 = 锚点位置 + 锚点之后真实流逝的时间。
  int get positionMs => _playing
      ? math.max(0, _anchorPos + DateTime.now().millisecondsSinceEpoch - _anchorWall)
      : _anchorPos;

  int get lyricIndex => lyricIndexAt(lines, math.max(0, positionMs + style.offsetMs));

  Future<void> handle(String method, Object? args) async {
    final a = args is Map ? Map<String, Object?>.from(args.cast<Object?, Object?>()) : const <String, Object?>{};
    switch (method) {
      case 'style':
        if (a['design'] != null) design = _size(a['design']);
        if (a['style'] is Map) style = CastStyle.fromJson(a['style'] as Map);
        final next = _rect(a['bounds']);
        final fs = a['fullscreen'] == true;
        // 换全屏/区域要重开窗（无边框样式原地切不干净），主 isolate 那边已经处理，这里只搬位置。
        if (next != bounds) {
          bounds = next;
          await windowManager.setBounds(next);
          // 同上：setBounds 会清掉置顶，搬完必须补回来，否则歌词窗会被前台应用盖住。
          await windowManager.setAlwaysOnTop(true);
        }
        fullscreen = fs;
        styleRev++;
      case 'lyric':
        lines = _lines(a['lines']);
        title = a['title'] as String?;
        artist = a['artist'] as String?;
        seat = a['seat'] as String?;
        durationMs = (a['durationMs'] as num?)?.toInt() ?? 0;
        lyricRev++;
      case 'tick':
        // 每次 tick 都是权威位置 + 当时的墙钟，直接重设锚点即可纠偏；主 isolate 一秒推一次。
        _anchorPos = (a['positionMs'] as num?)?.toInt() ?? _anchorPos;
        _anchorWall = (a['wallMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        _playing = a['playing'] == true;
        tickRev++;
        if (_playing && _tick == null) {
          // 走词 5 帧/秒足够，剩下靠锚点自己算，不必逐帧 IPC。
          _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => notifyListeners());
        } else if (!_playing) {
          _tick?.cancel();
          _tick = null;
        }
      case 'close':
        _tick?.cancel();
        _tick = null;
        unawaited(windowManager.destroy());
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

/// 行格式：`[起点, 文本, 行尾?, 逐字?]`，逐字为 `[起点, 终点, 文本]` 列表。
List<LyricLine> _lines(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is List && e.length >= 2)
        (
          startMs: (e[0] as num).toInt(),
          text: '${e[1]}',
          endMs: e.length >= 3 && e[2] is num ? (e[2] as num).toInt() : 0,
          words: e.length >= 4 ? _words(e[3]) : const <LyricWord>[],
        ),
  ];
}

List<LyricWord> _words(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is List && e.length >= 3)
        (startMs: (e[0] as num).toInt(), endMs: (e[1] as num).toInt(), text: '${e[2]}'),
  ];
}

/// 投放窗的画面：优先让 Chromium 排网页，网页起不来就退回 Flutter 自绘。
/// 退回不能让屏幕空着——设置里勾了屏就一定有词，原因带回主 isolate 显示出来。
class CastWindowView extends StatefulWidget {
  const CastWindowView({super.key, required this.model, this.onNote});

  final CastWindowModel model;
  final void Function(String reason)? onNote;

  @override
  State<CastWindowView> createState() => _CastWindowViewState();
}

class _CastWindowViewState extends State<CastWindowView> {
  ChromiumWebViewController? _controller;
  bool _pageReady = false;
  String? _failure;
  Size _lastBox = Size.zero;
  int _styleRev = -1;
  int _lyricRev = -1;
  int _tickRev = -1;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_sync);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (!await castWebInitialize()) {
      if (mounted) _fallback(l10n.castRuntimeMissing);
      return;
    }
    if (!mounted || _failure != null) return;
    final controller = ChromiumWebViewController(initialUrl: castPageUrl())
      ..onLoadingStateChanged = (loading, _, _) {
        if (!loading) _onLoaded();
      }
      ..onLoadError = (code, text, url) => _fallback(l10n.castPageLoadFailed(code, text));
    setState(() => _controller = controller);
  }

  /// 每次导航结束页面里的 window.enode 都是全新的，之前的 payload 全丢，要整份重推。
  void _onLoaded() {
    if (!mounted || _failure != null) return;
    _styleRev = -1;
    _lyricRev = -1;
    _tickRev = -1;
    _pageReady = true;
    _sync();
  }

  void _sync() {
    final controller = _controller;
    if (controller == null || !_pageReady || _failure != null) return;
    final m = widget.model;
    if (m.styleRev != _styleRev || _styleRev < 0) {
      _styleRev = m.styleRev;
      _push(controller, {
        'style': castWebStyle(m.style),
        'geometry': castWebGeometry(_box()),
      });
    }
    if (m.lyricRev != _lyricRev || _lyricRev < 0) {
      _lyricRev = m.lyricRev;
      _push(controller, castWebLyric(m.lines, title: m.title, artist: m.artist, seat: m.seat, durationMs: m.durationMs));
    }
    if (m.tickRev != _tickRev || _tickRev < 0) {
      _tickRev = m.tickRev;
      _push(controller, castWebTick(positionMs: m.anchorPositionMs, wallMs: m.anchorWallMs, playing: m.playing));
    }
  }

  /// CSS 视口就是 Flutter 的逻辑像素：字号按这块画面高度折算，才和自绘版同一个视觉大小。
  Size _box() => _lastBox.width > 0 && _lastBox.height > 0 ? _lastBox : widget.model.design;

  void _push(ChromiumWebViewController controller, Map<String, Object?> section) {
    final js = castApplyScript(section);
    controller.executeJavaScript(js).then((_) {}, onError: (Object e) => _fallback(l10n.castPushFailed('$e')));
  }

  void _fallback(String reason) {
    if (!mounted || _failure != null) return;
    final controller = _controller;
    _controller = null;
    _pageReady = false;
    setState(() => _failure = reason);
    unawaited(controller?.dispose());
    widget.onNote?.call(reason);
  }

  @override
  void dispose() {
    widget.model.removeListener(_sync);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || _failure != null) return _painted();
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        if (box != _lastBox) {
          _lastBox = box;
          // 视口尺寸变了，网页侧字号要按新高度重排。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _styleRev = -1;
              _sync();
            }
          });
        }
        return ChromiumWebView(controller: controller, onError: (e) => _fallback(l10n.castWebError('$e')));
      },
    );
  }

  Widget _painted() => AnimatedBuilder(
        animation: widget.model,
        builder: (context, _) => CastLyricView(
          style: widget.model.style,
          design: widget.model.design,
          lines: widget.model.lines,
          index: widget.model.lyricIndex,
          title: widget.model.title,
          artist: widget.model.artist,
          seat: widget.model.seat,
          positionMs: widget.model.positionMs,
          durationMs: widget.model.durationMs,
        ),
      );
}
