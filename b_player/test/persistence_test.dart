import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/edge/atomic_json.dart';
import 'package:b_player/edge/library_store.dart';
import 'package:b_player/edge/music_info.dart';
import 'package:b_player/state/self_playlist.dart';

PlaylistEntry _entry(String key) => PlaylistEntry(
      trackKey: key,
      title: key,
      artist: 'A',
      durationMs: 180000,
      sourceId: 'local',
    );

PlaylistSnapshot _snapshot({int index = 0, int positionMs = 0}) => PlaylistSnapshot(
      activeId: 'pl1',
      lists: [
        SelfPlaylist(
          id: 'pl1',
          name: '午市',
          mode: PlaylistMode.shuffle,
          tracks: [_entry('a'), _entry('b')],
          index: index,
          positionMs: positionMs,
          lastPlayedAtMs: 1234,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('enode_persist_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('AtomicJsonFile', () {
    test('写入后可读回，连续写入保留上一份备份', () async {
      final store = AtomicJsonFile(File(p.join(dir.path, 'a.json')));
      expect(await store.read(), isNull);

      await store.write({'v': 1});
      expect(await store.read(), {'v': 1});

      await store.write({'v': 2});
      expect(await store.read(), {'v': 2});
      final backup = File(p.join(dir.path, 'a.json.bak'));
      expect(await backup.exists(), isTrue);
      expect(jsonDecode(await backup.readAsString()), {'v': 1});
    });

    test('主文件损坏或为空时回退备份', () async {
      final file = File(p.join(dir.path, 'a.json'));
      final store = AtomicJsonFile(file);
      await store.write({'v': 1});
      await store.write({'v': 2});

      await file.writeAsString('{"v":');
      expect(await store.read(), {'v': 1}, reason: '半截 JSON 应读备份');

      await file.writeAsString('');
      expect(await store.read(), {'v': 1});

      await file.writeAsString('null');
      expect(await store.read(), isNull, reason: '合法 JSON 也照常返回，由调用方判断类型');
    });

    test('delete 清掉主文件、备份与临时文件', () async {
      final store = AtomicJsonFile(File(p.join(dir.path, 'a.json')));
      await store.write({'v': 1});
      await store.write({'v': 2});
      await store.delete();
      expect(await store.read(), isNull);
      expect(dir.listSync().whereType<File>(), isEmpty);
    });
  });

  group('PlaylistStore 拆分', () {
    test('结构与进度分文件，能合并读回', () async {
      final store = PlaylistStore(dir);
      final snapshot = _snapshot(index: 1, positionMs: 42000);
      await store.writeStructure(PlaylistStore.encodeStructure(snapshot));
      await store.writeState(PlaylistStore.encodeState(snapshot));

      final structure = File(p.join(dir.path, 'playlists.json'));
      final state = File(p.join(dir.path, 'playlist_state.json'));
      expect(await structure.exists(), isTrue);
      expect(await state.exists(), isTrue);

      final raw = await structure.readAsString();
      expect(raw.contains('positionMs'), isFalse, reason: '结构文件不该带高频进度');
      expect(raw.contains('tracks'), isTrue);

      final restored = await PlaylistStore(dir).load();
      expect(restored, isNotNull);
      final list = restored!.lists.single;
      expect(restored.activeId, 'pl1');
      expect(list.name, '午市');
      expect(list.mode, PlaylistMode.shuffle);
      expect(list.index, 1);
      expect(list.positionMs, 42000);
      expect(list.lastPlayedAtMs, 1234);
      expect([for (final t in list.tracks) t.trackKey], ['a', 'b']);
    });

    test('只写进度不动结构文件', () async {
      final store = PlaylistStore(dir);
      await store.writeStructure(PlaylistStore.encodeStructure(_snapshot()));
      final structure = File(p.join(dir.path, 'playlists.json'));
      final before = await structure.readAsString();

      await store.writeState(PlaylistStore.encodeState(_snapshot(index: 1, positionMs: 9000)));

      expect(await structure.readAsString(), before);
      final restored = await PlaylistStore(dir).load();
      expect(restored!.lists.single.positionMs, 9000);
    });

    test('结构文件损坏时回退备份，仍能读回列表', () async {
      final store = PlaylistStore(dir);
      await store.writeStructure(PlaylistStore.encodeStructure(_snapshot(positionMs: 100)));
      await store.writeStructure(PlaylistStore.encodeStructure(_snapshot(positionMs: 200)));
      await File(p.join(dir.path, 'playlists.json')).writeAsString('oops');

      final restored = await PlaylistStore(dir).load();
      expect(restored, isNotNull);
      expect(restored!.lists.single.name, '午市');
    });

    test('没有新文件时迁移旧 prefs，旧 key 保留一版', () async {
      final legacy = PlaylistStore.encode(_snapshot(index: 1, positionMs: 7000));
      SharedPreferences.setMockInitialValues({'playlists.v1': legacy});

      final restored = await PlaylistStore(dir).load();
      expect(restored, isNotNull);
      expect(restored!.lists.single.positionMs, 7000);

      expect(await File(p.join(dir.path, 'playlists.json')).exists(), isTrue);
      expect(await File(p.join(dir.path, 'playlist_state.json')).exists(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('playlists.v1'), legacy, reason: '回滚兜底，保留一版');

      final again = await PlaylistStore(dir).load();
      expect(again!.lists.single.positionMs, 7000);
    });

    test('旧 prefs 损坏时按空列表继续', () async {
      SharedPreferences.setMockInitialValues({'playlists.v1': '{oops'});
      expect(await PlaylistStore(dir).load(), isNull);
    });
  });

  group('LibraryStore', () {
    LibraryIndex index(String title) => LibraryIndex(
          root: r'D:\Music',
          tracks: [
            Track(
              trackKey: Track.keyFor('a.flac', sourceId: 'local'),
              sourceId: 'local',
              title: title,
              artist: 'A',
              durationMs: 1000,
              relPath: 'a.flac',
              absPath: r'D:\Music\a.flac',
            ),
          ],
          broken: 0,
          scannedAtMs: 1,
          tookMs: 2,
        );

    test('索引可写可读，主文件损坏时回退上一份', () async {
      final store = LibraryStore(dir.path);
      await store.write(index('old'));
      await store.write(index('new'));
      expect((await store.read())!.tracks.single.title, 'new');

      await store.file.writeAsString('{broken');
      expect((await store.read())!.tracks.single.title, 'old');
    });

    test('clear 同时清掉索引与备份', () async {
      final store = LibraryStore(dir.path);
      await store.write(index('a'));
      await store.write(index('b'));
      await store.clear();
      expect(await store.read(), isNull);
      expect(dir.listSync().whereType<File>(), isEmpty);
    });
  });
}