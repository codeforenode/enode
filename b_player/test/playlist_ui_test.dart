import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/config.dart';
import 'package:b_player/state/app_settings.dart';
import 'package:b_player/state/app_state.dart';
import 'package:b_player/state/self_playlist.dart';
import 'package:b_player/theme.dart';
import 'package:b_player/ui/shell.dart';

import 'l10n_harness.dart';

const _testMqtt = MqttConfig(enabled: false);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useTraditionalChinese();
  });

  testWidgets('新建列表、搜索添加、随机与时段设置都能落在状态里', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(mqtt: _testMqtt);
    final settings = AppSettings();
    C.use(Brightness.dark);
    addTearDown(settings.dispose);

    await tester.pumpWidget(localizedApp(
      theme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Shell(state: state, settings: settings),
      ),
    ));
    await tester.pump();

    expect(find.text(l10n.playlistNoLists), findsOneWidget);
    await tester.tap(find.text(l10n.newPlaylist));
    await tester.pumpAndSettle();
    expect(find.text(l10n.createPlaylistTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lunch');
    await tester.tap(find.text(l10n.newPlaylist).last);
    await tester.pumpAndSettle();

    expect(state.playlists, hasLength(1));
    expect(state.activePlaylist!.name, 'Lunch');
    expect(state.activePlaylist!.mode, PlaylistMode.sequential);
    expect(find.text(l10n.selfPlaylists), findsOneWidget);

    await tester.tap(find.text(l10n.searchAdd));
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchSongsTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), '夜曲');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    final addInDialog = find.descendant(
      of: find.byType(Dialog),
      matching: find.text(l10n.addToPlaylist),
    );
    expect(addInDialog, findsWidgets);
    await tester.tap(addInDialog.first);
    await tester.pumpAndSettle();
    expect(state.activePlaylist!.tracks, hasLength(1));
    expect(state.activePlaylist!.tracks.single.title, '夜曲之外');
    expect(find.text(l10n.alreadyInPlaylist), findsOneWidget);

    await tester.tap(find.text(l10n.done));
    await tester.pumpAndSettle();
    expect(find.text('夜曲之外'), findsOneWidget);

    await tester.tap(find.text(l10n.shuffle));
    await tester.pump();
    expect(state.activePlaylist!.mode, PlaylistMode.shuffle);

    await tester.tap(find.text(l10n.scheduleOff));
    await tester.pumpAndSettle();
    expect(find.text(l10n.scheduleTitle), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text(l10n.done));
    await tester.pumpAndSettle();
    expect(state.activePlaylist!.schedule.enabled, isTrue);

    expect(tester.takeException(), isNull, reason: '最小宽屏下不应溢出');

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
