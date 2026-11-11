import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_version.dart';
import 'desktop/cast_spike.dart';
import 'desktop/cast_window_main.dart';
import 'desktop/single_instance.dart';
import 'desktop/windows_host.dart';
import 'edge/config.dart';
import 'edge/library_bootstrap.dart';
import 'edge/player_engine.dart';
import 'l10n/l10n.dart';
import 'legal.dart';
import 'log.dart';
import 'state/app_settings.dart';
import 'state/app_state.dart';
import 'state/app_update.dart';
import 'theme.dart';
import 'ui/shell.dart';

/// 托盘「退出」的确认弹层要挂在根 Navigator 上。
final navigatorKey = GlobalKey<NavigatorState>();

/// 用主显示器的工作区（不含任务栏）居中主窗；单位为逻辑像素，与窗口坐标一致。
Future<void> _centerMainWindow() async {
  final display = await screenRetriever.getPrimaryDisplay();
  final visible = display.visibleSize ?? display.size;
  final origin = display.visiblePosition ?? Offset.zero;
  final size = await windowManager.getSize();
  final dx = visible.width > size.width ? (visible.width - size.width) / 2 : 0.0;
  final dy = visible.height > size.height ? (visible.height - size.height) / 2 : 0.0;
  await windowManager.setPosition(Offset(origin.dx + dx, origin.dy + dy));
}

Future<void> main(List<String> args) async {
  // 投放子引擎先分流：这里要是再走一遍单实例抢端口，抢不过就 exit(0)，会把主窗连同整个进程一起带走。
  if (args.isNotEmpty && args.first == 'multi_window') {
    // 按载荷形状分流：投放窗是 JSON 对象（tag=lyric），#49 台架还是它那个 JSON 数组。
    if (await castWindowMain(args)) return;
    await castSpikeWindowMain(args);
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  // 投放子窗在上一段就分流了，它们不写日志：同目录多进程追加同一个文件会互相打断，
  // 投放出问题的概率也远低于主进程。
  await EnodeLog.init();
  EnodeLog.bridgeConsole();
  _installErrorHandlers();
  EnodeLog.i(
    'app',
    '启动 v=${EnodeLog.version} os=${Platform.operatingSystem} debug=$kDebugMode',
  );
  registerAppLicenses();
  if (Platform.isWindows && castSpikeRequested(args)) {
    await runCastSpike();
    return;
  }
  // 托盘菜单在窗口起来前就要出文字，先把本机语言偏好读出来并绑定。
  final settings = AppSettings();
  await settings.load();
  bindL10n(resolveAppLocale(settings.language.locale));
  WindowsHost? desktop;
  if (Platform.isWindows) {
    desktop = WindowsHost(navigatorKey);
    await windowManager.ensureInitialized();
    // 第二个进程只负责把已有窗口叫起来，然后自己退场——曲库索引与 MQTT 只归一个进程持有。
    if (!await claimSingleInstance(onActivate: desktop.showWindow)) exit(0);
    // 首帧显示前就摆到屏幕中间，避免先闪在左上角再跳；窗口比工作区还大时贴住左上。
    try {
      await _centerMainWindow();
    } catch (e) {
      debugPrint('窗口居中失败：$e');
    }
    await desktop.start();
  }
  await loadAppVersion();
  MediaKit.ensureInitialized();
  LibraryBootstrap? bootstrap;
  try {
    bootstrap = await LibraryBootstrap.open();
  } catch (e) {
    debugPrint('曲库初始化失败：$e');
  }
  // 「广播」页存过就用本机参数；没存过就是未配置，不连 MQTT。
  MqttConfig? savedMqtt;
  try {
    savedMqtt = await MqttConfigStore.load();
  } catch (e) {
    debugPrint('MQTT 配置读取失败：$e');
  }
  runApp(BPlayerApp(
    mqtt: savedMqtt,
    bootstrap: bootstrap,
    engine: bootstrap == null ? null : MediaKitEngine(),
    desktop: desktop,
    settings: settings,
    checkUpdates: true,
  ));
  EnodeLog.i(
    'app',
    '曲库曲目=${bootstrap?.library.tracks.length ?? 0} '
    'mqtt已配置=${savedMqtt?.configured ?? false}',
  );
}

/// 未捕获异常一律落盘。没有这一步，界面异常只会让窗口消失，店家什么也提供不了。
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    EnodeLog.e('flutter', details.exceptionAsString(), details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    EnodeLog.e('dart', '未捕获的异步异常', error, stack);
    return true;
  };
}

class BPlayerApp extends StatefulWidget {
  const BPlayerApp({
    super.key,
    this.mqtt,
    this.bootstrap,
    this.engine,
    this.desktop,
    this.settings,
    this.checkUpdates = false,
  });

  /// 测试可注入（例如指向本地 broker 或关闭连接）；正式运行取本机保存的参数。
  final MqttConfig? mqtt;

  /// 正式运行的曲库装配；测试不传，改用演示曲库。
  final LibraryBootstrap? bootstrap;

  /// 播放后端；测试不传，保持无原生依赖的模拟推进。
  final AudioEngine? engine;

  /// Windows 托盘与单实例宿主；其他平台为 null。
  final WindowsHost? desktop;

  /// 本机偏好；正式运行在 runApp 前已加载，测试不传则由应用自己建一份。
  final AppSettings? settings;

  /// 正式运行开启启动更新检查；测试默认关闭，避免联网。
  final bool checkUpdates;

  @override
  State<BPlayerApp> createState() => _BPlayerAppState();
}

class _BPlayerAppState extends State<BPlayerApp> with WidgetsBindingObserver {
  late final AppState _state;
  late final AppSettings _settings;
  late final AppUpdateController _updates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = widget.settings ?? AppSettings();
    if (widget.settings == null) _settings.load();
    _settings.addListener(_onSettingsChanged);
    _applyLocale();
    _updates = AppUpdateController();
    _state = AppState(
      mqtt: widget.mqtt,
      library: widget.bootstrap?.library,
      localSource: widget.bootstrap?.source,
      onlineSource: widget.bootstrap?.online,
      webDav: widget.bootstrap?.webDav,
      engine: widget.engine,
    );
    // 出厂歌单在后台解析（首次要检索上游，几十秒），不阻塞首屏。
    if (!_state.demoMode) unawaited(_state.featured.prepare());
    // 投放只在 Windows 有意义：其他平台连屏都扫不到，别白扫还白写一次设置。
    if (Platform.isWindows) {
      _state.bindCastWindows();
      unawaited(_state.loadCast());
    }
    widget.desktop?.onBeforeExit = _shutDown;
  }

  void _applyLocale() =>
      bindL10n(resolveAppLocale(_settings.language.locale));

  void _onSettingsChanged() {
    _applyLocale();
    widget.desktop?.refreshMenu();
  }

  /// 托盘「退出」确认后、进程结束前：收投放窗、补发离线状态、断 MQTT，并留时间把包发出去。
  ///
  /// 每步单独兜底：一步失败不能把后面几步一起跳过，否则退出会停在半路。
  Future<void> _shutDown() async {
    try {
      await _state.closeCastWindows();
      EnodeLog.i('app', '退出：投放已收');
    } catch (e, st) {
      EnodeLog.e('app', '退出：收投放窗失败', e, st);
    }
    try {
      await _state.edge.publishOffline();
      EnodeLog.i('app', '退出：已补发离线状态');
    } catch (e, st) {
      EnodeLog.e('app', '退出：补发离线状态失败', e, st);
    }
    _state.dispose();
    EnodeLog.i('app', '退出：状态已释放');
    // 给 QoS1 的离线报文留出到达 broker 的时间。
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  void didChangePlatformBrightness() {
    if (_settings.themeMode == ThemeMode.system) setState(() {});
  }

  @override
  void dispose() {
    widget.desktop?.onBeforeExit = null;
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    _state.dispose();
    _updates.dispose();
    _settings.dispose();
    super.dispose();
  }

  ThemeMode get _mode => _settings.themeMode;

  Brightness get _brightness => switch (_mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final brightness = _brightness;
          C.use(brightness);
          return MaterialApp(
            title: 'eNode',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(brightness),
            locale: _settings.language.locale,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            localeListResolutionCallback: (locales, supported) =>
                resolveAppLocale(null, deviceLocales: locales),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(_settings.textSize.scale)),
              child: child!,
            ),
            home: AnimatedBuilder(
              animation: Listenable.merge([_state, _state.edge]),
              builder: (context, _) => Shell(
                state: _state,
                settings: _settings,
                updates: widget.checkUpdates ? _updates : null,
              ),
            ),
          );
        },
      );
}
