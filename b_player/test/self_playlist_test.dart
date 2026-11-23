import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/state/self_playlist.dart';

PlaylistEntry _entry(String key) => PlaylistEntry(
      trackKey: key,
      title: key,
      artist: 'A',
      durationMs: 180000,
      sourceId: 'local',
    );

void main() {
  test('时段支持普通区间、跨午夜与全天', () {
    final day = PlaylistSchedule(
      enabled: true,
      days: {1, 2, 3, 4, 5},
      windows: [const PlaylistWindow(9 * 60, 22 * 60)],
    );
    expect(day.isActiveAt(DateTime(2026, 11, 23, 8, 59)), isFalse);
    expect(day.isActiveAt(DateTime(2026, 11, 23, 9)), isTrue);
    expect(day.isActiveAt(DateTime(2026, 11, 23, 21, 59)), isTrue);
    expect(day.isActiveAt(DateTime(2026, 11, 23, 22)), isFalse);
    expect(day.isActiveAt(DateTime(2026, 11, 22, 10)), isFalse, reason: '周日未勾选');

    final overnight = PlaylistSchedule(
      enabled: true,
      days: {1},
      windows: [const PlaylistWindow(22 * 60, 2 * 60)],
    );
    expect(overnight.isActiveAt(DateTime(2026, 11, 23, 23)), isTrue);
    expect(overnight.isActiveAt(DateTime(2026, 11, 24, 1)), isTrue, reason: '跨午夜按前一天生效');
    expect(overnight.isActiveAt(DateTime(2026, 11, 24, 3)), isFalse);
    expect(overnight.isActiveAt(DateTime(2026, 11, 23, 21, 59)), isFalse);

    final allDay = PlaylistSchedule(
      enabled: true,
      days: {1},
      windows: [const PlaylistWindow(0, 0)],
    );
    expect(allDay.isActiveAt(DateTime(2026, 11, 23, 4)), isTrue);
    expect(allDay.isActiveAt(DateTime(2026, 11, 24, 4)), isFalse);
  });

  test('没启用或没选星期/时段都不会自动播放', () {
    final off = PlaylistSchedule.defaults();
    expect(off.enabled, isFalse);
    expect(off.isActiveAt(DateTime(2026, 11, 23, 10)), isFalse);

    final noDays = PlaylistSchedule(
      enabled: true,
      days: {},
      windows: [const PlaylistWindow(0, 1439)],
    );
    expect(noDays.canRun, isFalse);
    expect(noDays.isActiveAt(DateTime(2026, 11, 23, 10)), isFalse);

    final noWindows = PlaylistSchedule(enabled: true, days: {1});
    expect(noWindows.canRun, isFalse);
    expect(noWindows.isActiveAt(DateTime(2026, 11, 23, 10)), isFalse);
  });

  test('顺序循环，随机一轮不重复且不选当前曲', () {
    final list = SelfPlaylist(
      id: 'p',
      name: 'P',
      tracks: [for (final k in ['a', 'b', 'c', 'd']) _entry(k)],
    );
    expect(list.nextIndex(), 1);
    list.index = 3;
    expect(list.nextIndex(), 0);

    list.mode = PlaylistMode.shuffle;
    list.index = 2;
    final seen = <int>{};
    for (var i = 0; i < 3; i++) {
      final next = list.nextIndex();
      expect(next, inInclusiveRange(0, 3));
      expect(next, isNot(2), reason: '随机也要避开当前曲');
      seen.add(next);
    }
    expect(seen, {0, 1, 3}, reason: '一轮内其余曲目各出现一次');
  });

  test('增删与拖动后，当前曲索引跟着走', () {
    final list = SelfPlaylist(
      id: 'p',
      name: 'P',
      tracks: [for (final k in ['a', 'b', 'c']) _entry(k)],
      index: 1,
      positionMs: 5000,
    );
    expect(list.addTrack(_entry('a')), isFalse, reason: '同一首不重复加');
    expect(list.addTrack(_entry('d')), isTrue);

    list.moveTrack(0, 2);
    expect([for (final t in list.tracks) t.trackKey], ['b', 'c', 'a', 'd']);
    expect(list.current!.trackKey, 'b');
    expect(list.positionMs, 5000);

    list.removeTrackAt(0);
    expect(list.current!.trackKey, 'c', reason: '删掉当前曲后自动顶到下一首');
    expect(list.positionMs, 0);

    list.index = 99;
    list.normalize();
    expect(list.index, 0);
  });

  test('列表快照能往返保存顺序、时段和续播位置', () {
    final list = SelfPlaylist(
      id: 'pl1',
      name: '午市',
      mode: PlaylistMode.shuffle,
      schedule: PlaylistSchedule(
        enabled: true,
        days: {1, 3, 5},
        windows: [const PlaylistWindow(9 * 60, 12 * 60), const PlaylistWindow(22 * 60, 2 * 60)],
      ),
      tracks: [_entry('a'), _entry('b')],
      index: 1,
      positionMs: 42000,
      lastPlayedAtMs: 1000,
    );
    final raw = PlaylistStore.encode(
      PlaylistSnapshot(lists: [list], activeId: 'pl1'),
    );
    final restored = PlaylistSnapshot.fromJson(
      (const JsonDecoder().convert(raw)) as Map<String, Object?>,
    );

    expect(restored, isNotNull);
    final snapshot = restored!;
    expect(snapshot.activeId, 'pl1');
    final p = snapshot.lists.single;
    expect(p.name, '午市');
    expect(p.mode, PlaylistMode.shuffle);
    expect(p.schedule.enabled, isTrue);
    expect(p.schedule.days, {1, 3, 5});
    expect([for (final w in p.schedule.windows) '${w.startMinutes}-${w.endMinutes}'],
        ['540-720', '1320-120']);
    expect(p.index, 1);
    expect(p.positionMs, 42000);
    expect([for (final e in p.tracks) e.trackKey], ['a', 'b']);
  });
}
