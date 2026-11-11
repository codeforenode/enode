import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/app_version.dart';
import 'package:b_player/edge/config.dart';
import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/sources/lx_online_source.dart';
import 'package:b_player/main.dart';
import 'package:b_player/state/app_settings.dart';
import 'package:b_player/state/app_state.dart';
import 'package:b_player/state/app_update.dart';
import 'package:b_player/theme.dart';
import 'package:b_player/ui/shell.dart';

import 'l10n_harness.dart';

const _testMqtt = MqttConfig(enabled: false);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useTraditionalChinese();
  });

  testWidgets('窄屏一屏：播放 + 队列 + 音源条同屏，没有标签页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    expect(find.text(l10n.mqttNotConfigured), findsOneWidget);
    expect(find.text('搁浅之外'), findsNWidgets(2)); // 播放卡 + 队列首行
    expect(find.text('v$appVersion'), findsOneWidget);

    // 三段同屏，不再有「播放 / 曲库」两页切换
    expect(find.text(l10n.nowPlaying), findsOneWidget);
    expect(find.text(l10n.queue), findsOneWidget);
    expect(find.text(l10n.sourcesTitle), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    expect(find.text('曲库管理'), findsNothing);
    expect(find.text('WebDav'), findsNothing);
    expect(find.text('晴天之外'), findsNWidgets(2));
    expect(find.textContaining(l10n.timeLeft('')), findsOneWidget);

    // 底部音源条固定可见；窄屏点「管理」进整页
    expect(find.text(l10n.sourcesSummary(5000, 0)), findsOneWidget);
    await tester.tap(find.byKey(const Key('sources-manage')));
    await tester.pump();
    expect(find.text(l10n.localSourceTitle), findsOneWidget);
    expect(find.text(l10n.webdavSourceTitle), findsOneWidget);
    expect(find.text(l10n.demoLibrary), findsOneWidget);
    expect(find.text(l10n.webdavEmptyTitle), findsOneWidget);
    await tester.tap(find.text(l10n.done));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    expect(find.text('稻香之外'), findsNothing);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(find.text(l10n.paused), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('宽屏一屏：播放在左 · 队列在右 · 音源区在下方固定 190', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    expect(find.text('eNode'), findsOneWidget);
    expect(find.text(l10n.nowPlaying), findsOneWidget);
    expect(find.text(l10n.queue), findsOneWidget);
    expect(find.text(l10n.rescan), findsOneWidget);
    expect(find.text(l10n.changeFolder), findsOneWidget);
    expect(find.text(l10n.localSourceTitle), findsOneWidget);
    expect(find.text(l10n.webdavSourceTitle), findsOneWidget);
    expect(find.text(l10n.webdavEmptyTitle), findsOneWidget);

    expect(tester.getTopLeft(find.text(l10n.nowPlaying)).dx, lessThan(tester.getTopLeft(find.text(l10n.queue)).dx));
    expect(tester.getTopLeft(find.text(l10n.sourcesTitle)).dy,
        greaterThan(tester.getBottomLeft(find.text(l10n.queue)).dy));
    // 音源区固定 190 的外框（含 16 底部留白，面板本体 174）
    expect(tester.getSize(find.byKey(const Key('sources-panel'))).height, 174);
    expect(find.text(l10n.volume), findsOneWidget); // 宽屏才显示音量文字

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('最小宽屏 900×720：三区在英文下也不溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(mqtt: _testMqtt);
    final settings = AppSettings();
    C.use(Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      theme: buildTheme(Brightness.dark),
      home: Shell(state: state, settings: settings),
    ));
    await tester.pump();

    expect(find.byKey(const Key('sources-panel')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('sources-panel'))).height, 174);
    expect(find.byKey(const Key('local-rescan')), findsOneWidget);
    expect(find.byKey(const Key('webdav-add')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    settings.dispose();
  });

  testWidgets('播放卡显示同步歌词行', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    // _warmArt 取到整首 LRC 后才渲染：83s 落在第 10 句，上一句同时在屏
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('演示歌词'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置页：显示段可切主题字号，未解锁时无音源段，广播段可粘贴', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();

    expect(find.text(l10n.settingsTitle), findsOneWidget);
    expect(find.text(l10n.tabDisplay), findsOneWidget);
    expect(find.text(l10n.tabAbout), findsOneWidget);
    expect(find.text(l10n.tabBroadcast), findsOneWidget);
    expect(find.text(l10n.tabSources), findsNothing, reason: '未解锁时整段不出现');

    await tester.tap(find.text(l10n.tabBroadcast));
    await tester.pump();
    expect(find.text(l10n.mqttApply), findsOneWidget);
    expect(find.text(l10n.mqttClear), findsOneWidget);
    expect(find.text(l10n.mqttIntroUnconfigured), findsOneWidget);
    expect(find.text(l10n.mqttNotConfigured), findsWidgets); // 面板状态 + 弹层背后的顶栏
    await tester.tap(find.text(l10n.tabDisplay));
    await tester.pump();

    // 主题和语言各有「跟隨系統」，所以这一项会出现两次。
    expect(find.text(l10n.themeSystem), findsNWidgets(2));
    for (final label in [
      l10n.theme,
      l10n.themeDark,
      l10n.themeLight,
      l10n.textSize,
      l10n.textSizeSmall,
      l10n.textSizeMedium,
      l10n.textSizeLarge,
      l10n.textSizeXLarge,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('MQTT Broker'), findsNothing);
    expect(find.text('Client ID'), findsNothing);

    await tester.tap(find.text(l10n.themeLight));
    await tester.pump();
    await tester.tap(find.text(l10n.textSizeXLarge));
    await tester.pump();

    await tester.tap(find.text(l10n.done));
    await tester.pump();

    expect(find.text(l10n.settingsTitle), findsNothing);
    final scaler = MediaQuery.textScalerOf(tester.element(find.text(l10n.nowPlaying)));
    expect(scaler.scale(10), closeTo(13, 0.01));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置页按 Esc 关闭', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    expect(find.text(l10n.settingsTitle), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text(l10n.settingsTitle), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置页关于段：版本与节点，不露解锁提示', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    await tester.tap(find.text(l10n.tabAbout));
    await tester.pump();

    expect(find.text(l10n.aboutVersionNode), findsOneWidget);
    expect(find.text(l10n.aboutConnection), findsOneWidget);
    expect(find.text(l10n.aboutLibraryDir), findsOneWidget);
    // 测试进程没有初始化日志，曲库目录与日志目录都会落在「未设置」
    expect(find.text(l10n.notSet), findsWidgets);
    expect(find.text(l10n.aboutLogDir), findsOneWidget);
    expect(find.text(l10n.aboutOpenLog), findsOneWidget);
    expect(find.textContaining('连点上方版本号'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拖拽必须先确认才换位', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BPlayerApp(mqtt: _testMqtt));

    // 抓第 4 行（12 号桌那条晴天之外），长按后拖到第 2 行
    final grabbed = find.text('晴天之外').last;
    final g = await tester.startGesture(tester.getCenter(grabbed));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await g.moveTo(tester.getCenter(find.text('稻香之外')));
    await tester.pumpAndSettle();
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text(l10n.moveToPosition('晴天之外', 2)), findsOneWidget);
    final panel = find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;
    expect(tester.getSize(panel).width, lessThan(420));

    await tester.tap(find.text(l10n.confirm));
    await tester.pump(const Duration(milliseconds: 300));

    // 落定后第一条「晴天之外」应是 12 号桌那条
    final outerRow = find.ancestor(of: find.text('晴天之外').first, matching: find.byType(Row)).last;
    expect(find.descendant(of: outerRow, matching: find.text('12 号桌')), findsOneWidget);
    expect(find.text('稻香之外'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('音源段默认隐藏，点「关于」里的版本号解锁并直达', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final online = LxOnlineSource(client: MockClient((_) async => http.Response('{}', 200)));
    final state = AppState(mqtt: _testMqtt, library: Library([online]), onlineSource: online);
    final settings = AppSettings();
    C.use(Brightness.dark);

    await tester.pumpWidget(localizedApp(
      theme: buildTheme(Brightness.dark),
      home: Shell(state: state, settings: settings),
    ));

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    expect(find.text(l10n.tabSources), findsNothing);
    expect(find.byKey(const Key('appVersionTap')), findsNothing, reason: '主界面版本号只做展示');

    await tester.tap(find.text(l10n.tabAbout));
    await tester.pump();
    expect(find.text(l10n.tabSources), findsNothing, reason: '关于里的版本号才是入口');

    final version = find.byKey(const Key('aboutVersionTap'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text(l10n.tabSources), findsNothing, reason: '不足 5 次不解锁');

    await tester.tap(version);
    await tester.pump();

    // 解锁后直接落在「音源」段
    expect(find.text(l10n.tabSources), findsOneWidget);
    expect(find.text(l10n.onlineSourcesTitle), findsOneWidget);
    expect(find.text('保存'), findsNothing, reason: '改动即时生效，不再需要单独保存');

    await tester.ensureVisible(find.text('flac'));
    await tester.tap(find.text('flac'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(online.quality, 'flac');
    expect(online.enabledPlatformIds, {'kw', 'kg', 'mg', 'tx', 'wy'},
        reason: '平台不由用户开关，脚本支持多少就搜多少');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lx.quality'), 'flac');
    expect(prefs.getStringList('lx.platforms'), isNull, reason: '旧的平台勾选已清理');

    // 重启后重新隐藏
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    settings.dispose();

    final online2 = LxOnlineSource(client: MockClient((_) async => http.Response('{}', 200)));
    final state2 = AppState(mqtt: _testMqtt, library: Library([online2]), onlineSource: online2);
    final settings2 = AppSettings();
    await tester.pumpWidget(localizedApp(
      theme: buildTheme(Brightness.dark),
      home: Shell(state: state2, settings: settings2),
    ));
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    expect(find.text(l10n.tabSources), findsNothing);
    expect(find.text('flac'), findsNothing, reason: '没解锁就不该漏出音源内容');

    await tester.pumpWidget(const SizedBox());
    state2.dispose();
    settings2.dispose();
  });

  testWidgets('启动发现新版本提示一次，关于页保留状态和下载入口', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(mqtt: _testMqtt);
    final settings = AppSettings();
    final updates = AppUpdateController(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'tag_name': 'v9.9.9',
              'html_url': 'https://example.test/releases/v9.9.9',
              'assets': const [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
      currentVersion: () => '1.4.0',
    );

    await tester.pumpWidget(localizedApp(
      theme: buildTheme(Brightness.dark),
      home: Shell(state: state, settings: settings, updates: updates),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.updateAvailableTitle('v9.9.9')), findsOneWidget);

    await tester.tap(find.text(l10n.updateLater));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.updateAvailableTitle('v9.9.9')), findsNothing);

    await tester.tap(find.byTooltip(l10n.settingsTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.tabAbout));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.aboutUpdate), findsOneWidget);
    expect(find.text(l10n.aboutNewVersion('v9.9.9')), findsOneWidget);
    expect(find.text(l10n.aboutDownloadUpdate), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
    settings.dispose();
    updates.dispose();
  });
}
