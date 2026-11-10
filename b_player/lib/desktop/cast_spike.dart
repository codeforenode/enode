import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 歌词投放窗能力台架（一次性，验完删除）。
///
/// 要回答四件事：
/// 1. 插件另起引擎能不能真的样式化（无边框 / 置顶 / 不进任务栏 / 鼠标穿透）；
/// 2. 用 screen_retriever 的逻辑像素摆窗，落位是否正好盖住目标屏；
/// 3. 混合 DPI 下子窗的 devicePixelRatio 是否跟着自己那块屏走（不跟就会发虚）；
/// 4. 一个额外引擎的内存代价。
///
/// 启动方式：eNode.exe --cast-test（或环境变量 ENODE_CAST_SPIKE=1，方便 flutter run）。
/// 报告边收边写进进程当前目录的 cast_spike_report.txt；建 cast_spike_stop.txt 即收尾退进程。
const _castTag = 'cast';
const castSpikeFlag = '--cast-test';

// 报告和收尾标记都放临时目录，别在工程里留下要清理的调试产物。
String _spikePath(String name) =>
    '${Platform.environment['TEMP'] ?? Directory.current.path}/$name';

bool castSpikeRequested(List<String> args) =>
    args.contains(castSpikeFlag) || Platform.environment['ENODE_CAST_SPIKE'] == '1';

// 台架专用的分段开关：崩在哪一段就关掉哪一段再跑，不用反复改代码重编。
bool _skipStyle() => Platform.environment['ENODE_CAST_SKIP_STYLE'] == '1';
bool _skipRender() => Platform.environment['ENODE_CAST_SKIP_RENDER'] == '1';
bool _onlyOne() => Platform.environment['ENODE_CAST_ONLY_ONE'] == '1';

/// 只执行前 N 个窗口样式调用，用来逐台架定位是哪一步把进程干崩。
int _maxSteps() => int.tryParse(Platform.environment['ENODE_CAST_MAX_STEPS'] ?? '') ?? 999;

/// 1 = 按整屏尺寸摆窗（含任务栏那条），用来验「全屏投放能不能盖住任务栏」；默认只盖工作区。
bool _fullScreen() => Platform.environment['ENODE_CAST_FULL'] == '1';

/// 0 = 收到子窗收尾就立刻退进程（批量台架用），默认挂窗 3 分钟方便肉眼和截图。
int _holdSeconds() => int.tryParse(Platform.environment['ENODE_CAST_HOLD'] ?? '') ?? 180;

/// 主窗侧：每台显示器开一扇投放窗，收子窗回报，落盘后直接退进程。
Future<void> runCastSpike() async {
  final out = StringBuffer();
  final file = File(_spikePath('cast_spike_report.txt'));
  final self = await WindowController.fromCurrentEngine();
  final reports = <int, List<String>>{};
  final gate = Completer<void>();
  await self.setWindowMethodHandler((call) async {
    if (call.method != 'spikeReport') return null;
    final a = call.arguments as Map;
    final index = (a['index'] as int?) ?? -1;
    (reports[index] ??= <String>[]).add(a['line'] as String? ?? '$a');
    // 收到一条就立刻落盘：进程要是当场段错误，最后一条面包屑得留着。
    _write(file, out, reports);
    // 首条回报到手即说明子引擎回主 isolate 的通道是活的，此刻的 RSS 就是引擎增量。
    if (!gate.isCompleted) gate.complete();
    return null;
  });

  final displays = await screenRetriever.getAllDisplays();
  final mainView = _firstView();
  out.writeln('== eNode 投放窗台架 ==');
  out.writeln('主窗 windowId=${self.windowId}  dpr=${mainView?.devicePixelRatio}  '
      'RSS(建窗前)=${_rssMb()}MB');
  out.writeln('检出 ${displays.length} 台显示器：');
  for (var i = 0; i < displays.length; i++) {
    final d = displays[i];
    final vp = d.visiblePosition ?? Offset.zero;
    final vs = d.visibleSize ?? d.size;
    out.writeln('  #$i ${d.name}\n'
        '      id=${d.id}\n'
        '      size(整屏逻辑)=${_r(d.size.width)}x${_r(d.size.height)}  '
        'work=${_r(vs.width)}x${_r(vs.height)} @${_r(vp.dx)},${_r(vp.dy)}  '
        'scale=${d.scaleFactor}');
  }

  for (var i = 0; i < displays.length; i++) {
    final d = displays[i];
    final vp = d.visiblePosition ?? Offset.zero;
    final vs = d.visibleSize ?? d.size;
    final arg = jsonEncode([
      _castTag, self.windowId, i, d.name ?? '屏$i',
      vp.dx, vp.dy, vs.width, vs.height, (d.scaleFactor ?? 1).toDouble(),
      // 整屏尺寸（screen_retriever 只给 rcWork，不给 rcMonitor 的原点）+ 是否走全屏模式
      d.size.width, d.size.height, _fullScreen() ? 1 : 0,
    ]);
    final controller =
        await WindowController.create(WindowConfiguration(arguments: arg, hiddenAtLaunch: true));
    out.writeln('  #$i -> 子窗 ${controller.windowId}');
    // 一扇建完、子窗报“Z”再建下一扇：两扇同时改窗口样式会把整个进程干崩（段错误，无 WER 记录）。
    // 显示也交给子窗自己做，主 isolate 不再对同一个 HWND 调 ShowWindow。
    final ok = await _waitLine(reports, i, 'Z', const Duration(seconds: 12));
    out.writeln(ok ? '  #$i 子窗样式全部做完' : '  #$i !! 12 秒没等到 Z——子窗卡在样式某步或直接崩了');
    if (!ok || _onlyOne()) break;
  }

  out.writeln('主窗 RSS(建窗后)=${_rssMb()}MB');
  // 子窗分两轮回报：立刻一次、挪到位 1.5 秒后一次（DPI 变更消息可能是异步的）。
  // 投放窗一直挂着，报告每秒刷一次；外部建 cast_spike_stop.txt 或直接等满 3 分钟后收尾。
  final stop = File(_spikePath('cast_spike_stop.txt'));
  try {
    await gate.future.timeout(const Duration(seconds: 12));
    out.writeln('主窗 RSS(子窗回报到手)=${_rssMb()}MB');
  } on TimeoutException {
    out.writeln('!! 12 秒内没收到任何子窗回报——子引擎大概率起不来或已崩');
  }
  final hold = _holdSeconds();
  final deadline = DateTime.now().add(Duration(seconds: hold));
  while (hold > 0 && DateTime.now().isBefore(deadline) && !stop.existsSync()) {
    _write(file, out, reports);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  _write(file, out, reports);
  exit(0);
}

void _write(File file, StringBuffer head, Map<int, List<String>> reports) {
  final body = StringBuffer('$head\n== 子窗回报 ==\n');
  final keys = reports.keys.toList()..sort();
  for (final k in keys) {
    body.writeln('#$k：');
    final lines = reports[k]!;
    for (final l in lines) {
      body.writeln('   $l');
    }
    if (lines.length > 1) {
      final first = _dprOf(lines.first);
      final last = _dprOf(lines.last);
      body.writeln('   => dpr ${first ?? "?"} -> ${last ?? "?"}'
          '${first != null && last != null && (first - last).abs() > 0.01 ? "（挪屏后变了）" : ""}');
    }
  }
  file.writeAsStringSync(body.toString());
  // 每秒一次的进度没必要全部灌进控制台，等每台屏都收到两条回报再打一次。
  if (!_printed && reports.isNotEmpty && reports.values.every((l) => l.length >= 2)) {
    _printed = true;
    // ignore: avoid_print
    print('${file.path}\n$body');
  }
}

bool _printed = false;

/// 子窗侧：main() 最前面分流到这里，不再走曲库 / MQTT / 单实例那一套。
Future<void> castSpikeWindowMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  List<Object?> p;
  try {
    p = (jsonDecode(args.length >= 3 ? args[2] : '') as List).cast<Object?>();
  } catch (_) {
    p = const [];
  }
  if (p.length < 9) {
    runApp(_SpikeApp(body: _SpikeError('参数缺失：$args')));
    return;
  }
  final mainId = p[1] as String;
  final index = p[2] as int;
  final screenName = p[3] as String;
  final rect = Rect.fromLTWH(
    (p[4] as num).toDouble(), (p[5] as num).toDouble(),
    (p[6] as num).toDouble(), (p[7] as num).toDouble(),
  );
  final screenScale = (p[8] as num).toDouble();
  final full = p.length > 11 && p[11] == 1;
  // 全屏模式的目标：原点仍按 rcWork 估（拿不到 rcMonitor 原点），尺寸用整屏。
  final want = full
      ? Rect.fromLTWH(rect.left, rect.top, (p[9] as num).toDouble(), (p[10] as num).toDouble())
      : rect;
  final toMain = WindowController.fromWindowId(mainId);

  void report(String line) => toMain.invokeMethod('spikeReport', {'index': index, 'line': line});

  await windowManager.ensureInitialized();
  report('A 子引擎起来了');
  // 每步先报再做：进程当场崩了，报告里也能看到最后一步是哪一步。
  final actions = <({String name, Future<void> Function() run})>[
    (name: 'setTitle', run: () => windowManager.setTitle('eNode 投放自检 #$index')),
    // setFullScreen 的实现整段包在 if (!is_frameless_) 里：先 setAsFrameless 它就什么都不做了。
    // 所以全屏模式必须让它自己去变无边框，不能再提前调 setAsFrameless。
    if (!full) (name: 'setAsFrameless', run: () => windowManager.setAsFrameless()),
    (name: 'setResizable', run: () => windowManager.setResizable(false)),
    // 注意：window_manager 的 Windows 后端没有 setMovable，调了会 MissingPluginException。
    // 无边框 + 不可缩放的窗口本来也拖不动。
    (name: 'setMinimizable', run: () => windowManager.setMinimizable(false)),
    (name: 'setMaximizable', run: () => windowManager.setMaximizable(false)),
    (name: 'setClosable', run: () => windowManager.setClosable(false)),
    // setSkipTaskbar 会直接用 taskbar_ 指针对象，而 taskbar_ 只在 waitUntilReadyToShow 里创建；
    // 不先调它 → 子引擎里必 segfault（window_manager 0.5.2 上游缺陷，主窗因为我们从没调过才没暴露）。
    (name: 'waitUntilReadyToShow', run: () => windowManager.waitUntilReadyToShow()),
    (name: 'setSkipTaskbar', run: () => windowManager.setSkipTaskbar(true)),
    (name: 'setHasShadow', run: () => windowManager.setHasShadow(false)),
    (
      name: 'setBounds ${rect.left},${rect.top} ${rect.width}x${rect.height}',
      run: () => windowManager.setBounds(rect),
    ),
    // setFullScreen 用 MonitorFromWindow(..., DEFAULTTONEAREST) 决定盖哪块屏，
    // 所以必须先把窗口搬到目标屏上再调，否则两扇都会落到同一块屏。
    if (full) (name: 'setFullScreen(true)', run: () => windowManager.setFullScreen(true)),
    (name: 'setIgnoreMouseEvents', run: () => windowManager.setIgnoreMouseEvents(true)),
    // setIgnoreMouseEvents 只 SetWindowLong 加了 WS_EX_LAYERED，却没调 SetLayeredWindowAttributes；
    // 分层窗在设过 alpha 之前是整扇不画的（实测：置顶、样式全对、截图里啥都没有）。
    // 补一次 setOpacity(1.0) 才真正可见。
    (name: 'setOpacity(1.0)', run: () => windowManager.setOpacity(1.0)),
    (name: 'show', run: () => windowManager.show()),
    // 置顶必须排在 setBounds / show 之后：这两个在 Windows 后端里都写死了 SetWindowPos(HWND_TOP)，
    // 先把窗口插到非置顶层的最前面，WS_EX_TOPMOST 当场就被清掉了（实测 ex-style 从 0x8 变 0x0）。
    (name: 'setAlwaysOnTop', run: () => windowManager.setAlwaysOnTop(true)),
  ];
  for (var s = 0; s < actions.length; s++) {
    if (_skipStyle() || s >= _maxSteps()) break;
    final a = actions[s];
    report('→ ${a.name}');
    await a.run();
  }
  if (_skipRender()) {
    report('Z 已跳过 runApp');
    return;
  }
  report('→ runApp');
  runApp(_SpikeApp(
    body: _SpikeTest(
        index: index,
        screenName: screenName,
        screenScale: screenScale,
        want: want,
        report: report),
  ));
  report('Z 已 runApp');
}

ui.FlutterView? _firstView() {
  final views = ui.PlatformDispatcher.instance.views;
  return views.isEmpty ? null : views.first;
}

int _rssMb() => (ProcessInfo.currentRss / 1048576).round();

String _r(num v) => v.round().toString();

double? _dprOf(String line) {
  final m = RegExp(r'dpr=([\d.]+)').firstMatch(line);
  return m == null ? null : double.parse(m.group(1)!);
}

/// 等某个子窗报出以 [mark] 开头的一行，等不到就是它在某步卡住/崩了。
Future<bool> _waitLine(Map<int, List<String>> reports, int index, String mark, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (reports[index]?.any((l) => l.startsWith(mark)) ?? false) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: body),
      );
}

class _SpikeError extends StatelessWidget {
  const _SpikeError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: const TextStyle(color: Colors.red, fontSize: 14)));
}

class _SpikeTest extends StatefulWidget {
  const _SpikeTest({
    required this.index,
    required this.screenName,
    required this.screenScale,
    required this.want,
    required this.report,
  });

  final int index;
  final String screenName;
  final double screenScale;
  final Rect want;
  final void Function(String line) report;

  @override
  State<_SpikeTest> createState() => _SpikeTestState();
}

class _SpikeTestState extends State<_SpikeTest> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _flush('建帧即刻'));
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _flush('挪屏 1.5s 后');
    });
  }

  void _onTick(Duration elapsed) => setState(() => _frames++);

  Future<void> _flush(String when) async {
    final v = View.of(context);
    final size = await windowManager.getSize();
    final pos = await windowManager.getPosition();
    final want = widget.want;
    final top = await windowManager.isAlwaysOnTop();
    final vis = await windowManager.isVisible();
    widget.report('$when dpr=${v.devicePixelRatio} 缩放=${(widget.screenScale * 100).round()}% '
        '实际逻辑=${_r(size.width)}x${_r(size.height)} @${_r(pos.dx)},${_r(pos.dy)} '
        '目标=${_r(want.width)}x${_r(want.height)} @${_r(want.left)},${_r(want.top)} '
        '物理=${_r(size.width * v.devicePixelRatio)}x${_r(size.height * v.devicePixelRatio)} '
        '落位误差(逻辑px)=dx ${_r(pos.dx - want.left)} dy ${_r(pos.dy - want.top)} '
        'dw ${_r(size.width - want.width)} dh ${_r(size.height - want.height)}  '
        '视口=${_r(v.physicalSize.width)}x${_r(v.physicalSize.height)} 置顶=$top 可见=$vis RSS=${_rssMb()}MB');
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _SpikePainter(
          index: widget.index,
          screenName: widget.screenName,
          scale: widget.screenScale,
          dpr: View.of(context).devicePixelRatio,
          frames: _frames,
          now: DateTime.now(),
        ),
      );
}

class _SpikePainter extends CustomPainter {
  const _SpikePainter({
    required this.index,
    required this.screenName,
    required this.scale,
    required this.dpr,
    required this.frames,
    required this.now,
  });

  final int index;
  final String screenName;
  final double scale;
  final double dpr;
  final int frames;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF06110B));
    final edge = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // 两条对角线必须正好交于四角：窗口没严丝合缝盖住目标屏，四角就会露黑边或切出去。
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), edge);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), edge);
    canvas.drawRect(Offset.zero & size, edge);

    final big = '${index + 1}';
    canvas.drawParagraph(
      _text(big, size.height * 0.4, FontWeight.w700, const Color(0xFF3DDC84)),
      Offset(size.width / 2 - size.height * 0.18, size.height * 0.3),
    );
    canvas.drawParagraph(
      _text('投放窗 #$index · $screenName · 这块屏缩放 ${(scale * 100).round()}% · dpr $dpr',
          22, FontWeight.w500, Colors.white),
      Offset(28, size.height * 0.1),
    );
    // 小号密集文字：DPI 被 DWM 拉伸发虚，这一行最容易看出来。
    canvas.drawParagraph(
      _text('夜色落在酒杯上 0123456789 AaBb 歌词投放自检 abcdefghijklmnopqrstuvwxyz 1234567890',
          12, FontWeight.w400, const Color(0xFFB9C6BE)),
      Offset(28, size.height * 0.1 + 34),
    );
    final tc = '${_p2(now.minute)}:${_p2(now.second)}.${_p2((now.millisecond / 10).round())}';
    canvas.drawParagraph(_text(tc, 40, FontWeight.w700, Colors.white), Offset(28, size.height - 84));
    canvas.drawParagraph(
      _text('F$frames  12px 边框=穿透可点', 16, FontWeight.w400, const Color(0xFF7A8A80)),
      Offset(size.width - 260, size.height - 44),
    );
    const corners = ['左上', '右上', '左下', '右下'];
    for (var i = 0; i < 4; i++) {
      final x = (i & 1) == 0 ? 8.0 : size.width - 52.0;
      final y = i < 2 ? 6.0 : size.height - 34.0;
      canvas.drawParagraph(_text(corners[i], 14, FontWeight.w500, const Color(0xFFF5A524)),
          Offset(x, y));
    }
  }

  static String _p2(int v) => v.toString().padLeft(2, '0');

  ui.Paragraph _text(String s, double fontSize, FontWeight weight, Color color) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Microsoft YaHei'))
      ..pushStyle(ui.TextStyle(color: color, fontSize: fontSize, fontWeight: weight))
      ..addText(s);
    return builder.build()..layout(ui.ParagraphConstraints(width: 4000));
  }

  @override
  bool shouldRepaint(_SpikePainter old) =>
      old.now != now || old.frames != frames || old.dpr != dpr;
}
