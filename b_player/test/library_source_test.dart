import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/library_store.dart';
import 'package:b_player/edge/sources/local_directory_source.dart';

class _FakeSource extends MusicSource {
  _FakeSource(this.id, {this.failAudio = false});

  @override
  final String id;
  final bool failAudio;
  int audioCalls = 0;

  @override
  String get kind => 'fake';
  @override
  String get label => id;
  @override
  Set<MusicSourceCapability> get capabilities => const {MusicSourceCapability.audio};

  @override
  Future<Uri> audioUri(Track track) async {
    audioCalls++;
    if (failAudio) throw const MusicSourceException('取播放地址失败');
    return Uri.parse('fake://$id/${track.trackKey}');
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('b_player_lib_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('本地音源：文件名回退 / LRC 匹配 / 增量 / 缺失统计 / 索引落盘', () async {
    final music = Directory(p.join(tmp.path, 'music'))..createSync();
    File(p.join(music.path, 'A - B.mp3')).writeAsStringSync('not really mp3');
    File(p.join(music.path, 'A - B.lrc')).writeAsStringSync('[00:00.00]hello');
    File(p.join(music.path, 'nocase.MP3')).writeAsStringSync('still not mp3');
    File(p.join(music.path, 'nocase.lrc')).writeAsStringSync('[00:01.00]case insensitive');

    final store = LibraryStore(p.join(tmp.path, 'index'));
    final source = LocalDirectorySource(root: music.path, store: store);
    await source.load();

    final first = await source.scan();
    expect(first.error, isNull);
    expect(first.canceled, isFalse);
    expect(first.tracks.length, 2);

    final ab = first.tracks.firstWhere((t) => t.relPath == 'A - B.mp3');
    expect(ab.title, 'B');
    expect(ab.artist, 'A');
    expect(ab.sourceId, 'local');
    expect(ab.lyricRel, isNotNull);
    expect((await source.lyric(ab)).lyric, contains('hello'));

    final nocase = first.tracks.firstWhere((t) => t.relPath == 'nocase.MP3');
    expect(nocase.lyricRel, isNotNull);
    expect((await source.lyric(nocase)).lyric, contains('case insensitive'));

    expect((await source.audioUri(ab)).toFilePath(), ab.absPath);
    expect((await source.search('B')).total, 1);
    expect((await source.search('nocase')).total, 1);

    // 第二次扫描走增量复用，结果与首次一致。
    final second = await source.scan();
    expect(second.tracks.length, 2);
    expect(second.broken, 0);

    // 删除一个文件后，旧索引里消失的项计入缺失。
    File(p.join(music.path, 'nocase.MP3')).deleteSync();
    final third = await source.scan();
    expect(third.tracks.length, 1);
    expect(third.broken, 1);

    final index = await store.read();
    expect(index, isNotNull);
    expect(p.normalize(index!.root), p.normalize(music.path));
    expect(index.tracks.length, 1);
    expect(index.tracks.single.trackKey, ab.trackKey);

    // 重启后直接读索引，不扫盘也能拿到曲库。
    final reopened = LocalDirectorySource(root: music.path, store: store);
    await reopened.load();
    expect((await reopened.listTrackKeys()).length, 1);
    expect((await reopened.fetchTracks([ab.trackKey])).single.title, 'B');
  });

  test('音源解析：曲目自带音源失败后回退到其它音源', () async {
    final tracks = [
      Track(trackKey: 't1', sourceId: 'a', title: '晴天', artist: '周杰伦', durationMs: 1000),
    ];
    final lib = Library([_FakeSource('a', failAudio: true), _FakeSource('b')], tracks: tracks);

    final uri = await lib.audioUriFor('t1');
    expect(uri.toString(), 'fake://b/t1');
    expect(lib.sourceLabelFor('t1'), 'a');
  });

  test('直链缓存：命中复用、并发合并、refresh 与清空都重新取链', () async {
    final tracks = [
      Track(trackKey: 't1', sourceId: 'a', title: '晴天', artist: '周杰伦', durationMs: 1000),
    ];
    final source = _FakeSource('a');
    final lib = Library([source], tracks: tracks);

    await lib.audioUriFor('t1');
    await lib.audioUriFor('t1');
    expect(source.audioCalls, 1, reason: '10 分钟内复用直链');

    await Future.wait([lib.audioUriFor('t1', refresh: true), lib.audioUriFor('t1', refresh: true)]);
    expect(source.audioCalls, 2);

    lib.clearAudioCache();
    await lib.audioUriFor('t1');
    expect(source.audioCalls, 3);

    lib.invalidateAudio('t1');
    await lib.audioUriFor('t1');
    expect(source.audioCalls, 4, reason: '引擎打不开时作废缓存，下次重新取链');
  });

  test('直链取失败不写缓存：音源修好后同一首立刻能再试', () async {
    final tracks = [
      Track(trackKey: 't1', sourceId: 'a', title: '晴天', artist: '周杰伦', durationMs: 1000),
    ];
    final source = _FakeSource('a', failAudio: true);
    final lib = Library([source], tracks: tracks);

    expect(await lib.audioUriFor('t1'), isNull);
    expect(await lib.audioUriFor('t1'), isNull);
    expect(source.audioCalls, 2, reason: '失败结果不进缓存');
  });
}
