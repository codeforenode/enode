import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/state/app_settings.dart';
import 'package:b_player/state/app_state.dart';
import 'package:b_player/state/cast_settings.dart';
import 'package:b_player/theme.dart';
import 'package:b_player/ui/cast_lyric_view.dart';
import 'package:b_player/ui/screen_cast_panel.dart';
import 'package:b_player/ui/settings_dialog.dart';

import 'l10n_harness.dart';

const _mqtt = MqttConfig(enabled: false);

// 两块假屏：和旧投放测试同一组尺寸，拖动的像素换算能直接用整数验。
const _main = CastMonitor(
  id: 'main',
  name: r'\\.\DISPLAY1',
  workOrigin: Offset.zero,
  workSize: Size(1920, 1040),
  fullSize: Size(1920, 1080),
  scale: 1,
);
const _second = CastMonitor(
  id: 'second',
  name: r'\\.\DISPLAY2',
  workOrigin: Offset(1920, 0),
  workSize: Size(1600, 852),
  fullSize: Size(1600, 900),
  scale: 1.5,
);

AppState _state(List<CastMonitor> monitors, {CastSettings? cast}) {
  final state = AppState(mqtt: _mqtt);
  state.applyCastScan(monitors, aligned: cast);
  return state;
}

/// 面板是三栏 + Expanded：必须给一块有界的高度，不能像旧面板那样塞进滚动视图。
Future<void> _pumpPanel(WidgetTester tester, AppState state) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  C.use(Brightness.dark);
  await tester.pumpWidget(localizedApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ScreenCastPanel(state: state),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpSettings(WidgetTester tester, AppState state) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  C.use(Brightness.dark);
  final settings = AppSettings();
  addTearDown(settings.dispose);
  await tester.pumpWidget(localizedApp(
    theme: buildTheme(Brightness.dark),
    home: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showSettings(
            context,
            state: state,
            settings: settings,
            onlineUnlocked: false,
            onUnlockOnline: () {},
          ),
          child: const Text('打开设置'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打开设置'));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 面板里的改动攒 250ms 才落盘；演示走词的秒表一直在跑，不能用 pumpAndSettle。
Future<void> _flushed(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// 收尾先拆树（cancels 演示/界面秒表），再 dispose。
Future<void> _close(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox());
  state.dispose();
}

/// 从「新增素材」菜单里挑一种类型。菜单没开时按钮在工具栏最左边。
Future<void> _addViaMenu(WidgetTester tester, String typeLabel) async {
  await tester.tap(find.text(l10n.screenAddMaterial));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.tap(find.descendant(of: find.byType(MenuItemButton), matching: find.text(typeLabel)).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// 属性段在右栏滚动视图里，点之前先滚过去。
Future<void> _tapInInspector(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useTraditionalChinese();
  });

  testWidgets('没扫到萤幕时不出现编辑器，只给重扫入口', (tester) async {
    final state = _state(const []);
    await _pumpPanel(tester, state);
    expect(find.text(l10n.castNoMonitors), findsOneWidget);
    expect(find.text(l10n.screenAddMaterial), findsNothing);
    expect(find.text(l10n.screenScreens), findsNothing);
    await _close(tester, state);
  });

  testWidgets('概览报屏数/素材/投放，左栏列出两块屏', (tester) async {
    final state = _state(const [_main, _second]);
    await _pumpPanel(tester, state);
    expect(find.text(l10n.castTitle), findsOneWidget);
    expect(find.text(l10n.screenSummary(2, 1, 0)), findsOneWidget);
    expect(find.text(l10n.screenEditOnly), findsOneWidget);
    expect(find.text(l10n.screenCount(2)), findsOneWidget);
    expect(find.text(_main.name), findsWidgets);
    expect(find.text(_second.name), findsWidgets);
    expect(find.text(l10n.screenLayersEmpty), findsOneWidget);
    expect(find.text(l10n.screenShelf), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('勾选屏才投放，并给空屏补一条歌词', (tester) async {
    final state = _state(const [_main, _second]);
    await _pumpPanel(tester, state);
    expect(find.text(l10n.screenCastingValue(0, 2)), findsOneWidget);

    // 没有总开关了，每台屏卡各一个开关。
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await _flushed(tester);
    expect(state.cast.targetFor(_main.id).enabled, isTrue);
    expect(state.cast.placementsOn(_main.id).length, 1, reason: '空屏自动补默认歌词');
    expect(find.text(l10n.screenCastingValue(1, 2)), findsOneWidget);
    expect(find.byType(CastLyricLayer), findsOneWidget);
    expect(find.text(l10n.screenLayersCount(1)), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('新增歌词：画布出字、图层面板可选，属性里没有背景和座位号', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    await _addViaMenu(tester, l10n.screenTypeLyric);

    expect(find.byType(CastLyricLayer), findsOneWidget);
    expect(find.text(l10n.screenLayersCount(1)), findsOneWidget);
    expect(find.text(l10n.screenSummary(1, 2, 1)), findsOneWidget);

    await _flushed(tester);
    final placed = state.cast.placementsOn(_main.id).single;
    expect(placed.materialId, isNot(CastMaterial.defaultLyric.id));

    expect(find.text(l10n.screenLyricNoBgNote), findsOneWidget);
    expect(find.text(l10n.castShowSeat), findsNothing, reason: '歌词附加属性里不该再有座位号');
    expect(find.text(l10n.castBgGradient), findsNothing, reason: '背景靠叠加别的素材，歌词不再自带背景');
    expect(find.text(l10n.castShowTitle), findsOneWidget);
    expect(find.text(l10n.castShowArtist), findsOneWidget);
    expect(find.text(l10n.castFontSize), findsOneWidget);
    expect(find.text(l10n.castLineGap), findsOneWidget);
    expect(find.text(l10n.castTextWidth), findsOneWidget);
    expect(find.text(l10n.castTextHeight), findsOneWidget);
    expect(find.text(l10n.castOtherOpacity), findsOneWidget);

    await _tapInInspector(tester, find.text(l10n.screenLineCount(1)));
    await _flushed(tester);
    expect(state.cast.materials.last.style.lines, 1);
    await _close(tester, state);
  });

  testWidgets('五种素材各自给出专属属性段', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);

    await _addViaMenu(tester, l10n.screenTypeUrl);
    expect(find.text(l10n.screenUrlReloadHint), findsOneWidget);
    expect(find.text('${l10n.screenTypeUrl} · ${l10n.screenUsageSingle}'), findsOneWidget);

    await _addViaMenu(tester, l10n.screenTypeImage);
    expect(find.text(l10n.screenImageBgNote), findsOneWidget);
    expect(find.text('${l10n.screenTypeImage} · ${l10n.screenUsageSingle}'), findsOneWidget);

    await _addViaMenu(tester, l10n.screenTypeVideo);
    expect(find.text(l10n.screenMuteOthersNote), findsOneWidget);
    expect(find.text('${l10n.screenTypeVideo} · ${l10n.screenUsageSingle}'), findsOneWidget);

    await _addViaMenu(tester, l10n.screenTypeText);
    expect(find.text(l10n.screenTextPlaceholder), findsOneWidget);
    expect(find.text('${l10n.screenTypeText} · ${l10n.screenUsageSingle}'), findsOneWidget);

    await _flushed(tester);
    expect(find.text(l10n.screenToolbarCounts(4, 1, 1)), findsOneWidget);
    expect(find.text(l10n.screenSummary(1, 5, 4)), findsOneWidget, reason: '默认歌词 + 四种新素材');

    // 同一屏两路重负载：屏卡和工具栏都要提醒。
    expect(find.text(l10n.screenPerfWarning(1, 1)), findsNothing, reason: '各一路还不算超');
    await _addViaMenu(tester, l10n.screenTypeVideo);
    await _flushed(tester);
    expect(find.text(l10n.screenPerfWarning(1, 2)), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('没投到任何屏的素材可以从架上删掉', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    // 默认歌词没投到屏上，一开始就能删；新加的素材在投放中，不该出现删除按钮。
    expect(find.byTooltip(l10n.screenDeleteMaterial), findsOneWidget);
    expect(find.byTooltip(l10n.screenAddLayer), findsOneWidget, reason: '图层面板标题带新增入口');
    await _addViaMenu(tester, l10n.screenTypeText);
    expect(find.byTooltip(l10n.screenDeleteMaterial), findsOneWidget, reason: '还在用就不给删');

    // 图层行和右侧检查器各有一个删除入口；这里点图层行内那个。
    final rowDelete = find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.byTooltip(l10n.screenDeleteLayer),
    );
    expect(rowDelete, findsOneWidget);
    await tester.tap(rowDelete);
    await tester.pump();
    await _flushed(tester);
    expect(state.cast.placements, isEmpty);
    expect(find.byTooltip(l10n.screenDeleteMaterial), findsNWidgets(2));

    await tester.tap(find.byTooltip(l10n.screenDeleteMaterial).last);
    await tester.pump();
    await _flushed(tester);
    expect(state.cast.materials.map((m) => m.id), [CastMaterial.defaultLyric.id]);
    expect(find.byTooltip(l10n.screenDeleteMaterial), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('同一屏只保留一路有声音', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);

    Future<void> soundOn() async {
      // 「聲音」也会出现在图层的小标签里，必须限定在本屏播放那一段。
      final section =
          find.ancestor(of: find.text(l10n.screenSectionSound), matching: find.byType(Column)).first;
      final sw = find.descendant(of: section, matching: find.byType(Switch)).first;
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(sw);
      await tester.pump();
      await _flushed(tester);
    }

    await _addViaMenu(tester, l10n.screenTypeVideo);
    await soundOn();
    var videos = state.cast.placements.where((p) => p.sound).toList();
    expect(videos.length, 1);

    await _addViaMenu(tester, l10n.screenTypeVideo);
    await soundOn();
    videos = state.cast.placements.where((p) => p.sound).toList();
    expect(videos.length, 1, reason: '新开声音要把前一路静音');
    expect(state.cast.placementsOn(_main.id).last.sound, isTrue);
    await _close(tester, state);
  });

  testWidgets('拖动素材会挪位置，拖出边界会夹住', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    await _addViaMenu(tester, l10n.screenTypeLyric);
    await _flushed(tester);

    final box = tester.getSize(find.byType(CastLyricLayer));
    // 默认 x=.25、宽=.5；手势启动会吃掉一段 slop，所以刻意多拖 40px。
    await tester.drag(find.byType(CastLyricLayer), Offset(-box.width / 2 - 40, 0));
    await tester.pump();
    await _flushed(tester);
    expect(state.cast.placementsOn(_main.id).single.x, closeTo(0, .001));
    await _close(tester, state);
  });

  testWidgets('横向拖动跟手：细小位移 1:1 落到位置上', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    await _addViaMenu(tester, l10n.screenTypeLyric);
    await _flushed(tester);

    final lyric = find.byType(CastLyricLayer);
    final before = state.cast.placementsOn(_main.id).single;
    final stageWidth = tester.getSize(lyric).width / before.width;
    final gesture = await tester.startGesture(tester.getCenter(lyric), kind: PointerDeviceKind.mouse);
    // 第一下越过拖拽判定阈值（这段会被手势启动吃掉），之后每步 6px 都应原样落到 x 上。
    await gesture.moveBy(const Offset(6, 0));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(6, 0));
    }
    await gesture.up();
    await _flushed(tester);

    final after = state.cast.placementsOn(_main.id).single;
    expect((after.x - before.x) * stageWidth, closeTo(24, .5));
    expect(after.y, before.y);
    await _close(tester, state);
  });

  testWidgets('拖动中只更新画布，整块面板不重建', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    await _addViaMenu(tester, l10n.screenTypeLyric);
    await _flushed(tester);

    final panel = tester.element(find.byType(ScreenCastPanel));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(CastLyricLayer)),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(6, 0));
    await tester.pump();

    final before = tester.getTopLeft(find.byType(CastLyricLayer));
    await gesture.moveBy(const Offset(8, 0));
    expect(panel.dirty, isFalse, reason: '指针移动只该脏画布这一层');
    await tester.pump();
    // 画布照常跟着指针走，只是面板其余部分没被卷进来。
    expect(tester.getTopLeft(find.byType(CastLyricLayer)).dx - before.dx, closeTo(8, .01));
    await gesture.up();
    await _flushed(tester);
    await _close(tester, state);
  });

  testWidgets('选中后按 Delete 删掉这一层', (tester) async {
    final state = _state(const [_main]);
    await _pumpPanel(tester, state);
    await _addViaMenu(tester, l10n.screenTypeText);

    await tester.tap(find.text(l10n.screenEmptyMaterial));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await _flushed(tester);
    expect(state.cast.placementsOn(_main.id), isEmpty);
    expect(find.text(l10n.screenLayersEmpty), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('预设两份网址：屏卡报数量、工具栏给性能提醒', (tester) async {
    const url1 = CastMaterial(id: 'u1', type: CastMaterialType.url, name: '看板', url: 'https://a.test');
    const url2 = CastMaterial(id: 'u2', type: CastMaterialType.url, name: '看板2', url: 'https://b.test');
    const cast = CastSettings(
      enabled: true,
      targets: [CastTarget(monitorId: 'main', name: r'\\.\DISPLAY1', enabled: true)],
      materials: [url1, url2],
      placements: [
        CastPlacement(id: 'p1', materialId: 'u1', screenId: 'main', x: .05, y: .05, width: .4, height: .4, z: 1),
        CastPlacement(id: 'p2', materialId: 'u2', screenId: 'main', x: .55, y: .05, width: .4, height: .4, z: 2),
      ],
    );
    final state = _state(const [_main], cast: cast);
    await _pumpPanel(tester, state);
    expect(find.text(l10n.screenLiveSync), findsOneWidget);
    expect(find.text(l10n.screenUrlBadge(2)), findsOneWidget);
    expect(find.text(l10n.screenPerfWarning(2, 0)), findsOneWidget);
    expect(find.text(l10n.screenLoadMid), findsOneWidget);
    await _close(tester, state);
  });

  testWidgets('设置页只扫到屏时才出现「萤幕管理」', (tester) async {
    final none = _state(const []);
    await _pumpSettings(tester, none);
    expect(find.text(l10n.tabCast), findsNothing);
    await _close(tester, none);

    final state = _state(const [_main, _second]);
    await _pumpSettings(tester, state);
    await tester.tap(find.text(l10n.tabCast));
    await tester.pump();
    expect(find.text(l10n.castTitle), findsWidgets);
    expect(find.text(l10n.screenAddMaterial), findsOneWidget);
    await _close(tester, state);
  });
}
