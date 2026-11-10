import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/edge/featured.dart';
import 'package:b_player/edge/library.dart';

/// 非列表型音源才会被 `Library.searchAsync` 在线查询，正好模拟 lx 音源。
class _FakeOnline extends MusicSource {
  _FakeOnline(this.catalog);

  final List<Track> catalog;
  int searches = 0;

  @override
  String get id => 'lx';
  @override
  String get kind => 'online';
  @override
  String get label => 'fake';
  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.search,
        MusicSourceCapability.audio,
      };

  @override
  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) async {
    searches++;
    final q = keyword.trim().toLowerCase();
    final hits = [
      for (final t in catalog)
        if (t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)) t,
    ];
    return MusicSearchPage(items: hits, total: hits.length, page: page, limit: limit);
  }
}

Track track({
  required String title,
  required String artist,
  int durationMs = 240000,
  String? trackKey,
  String platform = 'tx',
  String songId = 's1',
}) =>
    Track(
      trackKey: trackKey ?? Track.keyFor('$platform:$songId', sourceId: 'lx'),
      title: title,
      artist: artist,
      durationMs: durationMs,
      sourceId: 'lx',
      extra: {'platform': platform, 'songId': songId},
    );

String seedJson(List<Map<String, Object?>> tracks) => jsonEncode({
      'v': 1,
      'id': 'test',
      'tracks': tracks,
    });

Map<String, Object?> seedEntry(
  String title,
  String artist, {
  Object? durationMs = 240000,
  String? trackKey,
}) =>
    {
      'title': title,
      'artist': artist,
      'durationMs': ?durationMs,
      'trackKey': ?trackKey,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('指纹一致时直接采用候选曲目，并把 key 注册进曲库', () async {
    final hit = track(title: '晴天', artist: '周杰伦', songId: '99');
    final source = _FakeOnline([hit]);
    final library = Library([source]);
    final service = FeaturedService(
      library: library,
      loadSeed: () async => seedJson([
        seedEntry('晴天', '周杰伦', durationMs: 269000, trackKey: hit.trackKey),
      ]),
      cacheFile: () async => null,
    );

    await service.prepare();

    expect(service.ready, isTrue);
    expect(service.tracks.map((t) => t.trackKey), [hit.trackKey]);
    // 关键：解析出来的曲目必须能被 byKey 找到，否则 C 端点歌必然失败。
    expect(library.byKey(hit.trackKey), isNotNull);
  });

  test('指纹对不上时按歌名+歌手+时长兜底', () async {
    final hit = track(title: '成都', artist: '赵雷', durationMs: 328000);
    final source = _FakeOnline([
      // 同歌手的另一个版本（时长差 28s）：指纹不符且时长偏离，应被跳过
      track(title: '成都', artist: '赵雷', durationMs: 300000, trackKey: 'lx:stale', songId: 'other'),
      hit,
    ]);
    final library = Library([source]);
    final service = FeaturedService(
      library: library,
      loadSeed: () async => seedJson([
        seedEntry('成都', '赵雷', durationMs: 328000, trackKey: 'lx:000000000000'),
      ]),
      cacheFile: () async => null,
    );

    await service.prepare();

    expect(service.tracks.map((t) => t.trackKey), [hit.trackKey]);
  });

  test('时长偏差过大的翻唱/现场版不纳入', () async {
    final source = _FakeOnline([
      track(title: '晴天', artist: '周杰伦', durationMs: 300000, songId: 'live'),
    ]);
    final library = Library([source]);
    final service = FeaturedService(
      library: library,
      loadSeed: () async => seedJson([seedEntry('晴天', '周杰伦', durationMs: 269000)]),
      cacheFile: () async => null,
    );

    await service.prepare();

    expect(service.tracks, isEmpty);
    expect(service.failed, 1);
    expect(service.ready, isTrue);
  });

  test('时长写成字符串也能读，歌手名大小写与标点不影响匹配', () async {
    final hit = track(title: '光年之外', artist: 'G.E.M.邓紫棋', durationMs: 235000);
    final source = _FakeOnline([hit]);
    final library = Library([source]);
    final service = FeaturedService(
      library: library,
      loadSeed: () async => seedJson([
        seedEntry('光年之外', 'gem邓紫棋', durationMs: '235000'),
      ]),
      cacheFile: () async => null,
    );

    await service.prepare();

    expect(service.tracks.length, 1);
    expect(service.tracks.single.durationMs, 235000);
  });

  test('解析结果落盘后，下次启动不再打上游检索', () async {
    final dir = await Directory.systemTemp.createTemp('featured_test');
    addTearDown(() => dir.delete(recursive: true));
    final cache = File('${dir.path}/featured.cache.json');
    final hit = track(title: '后来', artist: '刘若英', durationMs: 309000);
    final seed = seedJson([seedEntry('后来', '刘若英', durationMs: 309000)]);

    final source1 = _FakeOnline([hit]);
    final service1 = FeaturedService(
      library: Library([source1]),
      loadSeed: () async => seed,
      cacheFile: () async => cache,
    );
    await service1.prepare();
    expect(service1.tracks.length, 1);
    expect(await cache.exists(), isTrue);
    final firstRound = source1.searches;
    expect(firstRound, greaterThan(0));

    final source2 = _FakeOnline([hit]);
    final library2 = Library([source2]);
    final service2 = FeaturedService(
      library: library2,
      loadSeed: () async => seed,
      cacheFile: () async => cache,
    );
    await service2.prepare();

    expect(source2.searches, 0, reason: '命中缓存就不该再检索上游');
    expect(service2.tracks.map((t) => t.trackKey), [hit.trackKey]);
    expect(library2.byKey(hit.trackKey), isNotNull);
  });

  test('种子内容变了缓存失效，重新解析', () async {
    final dir = await Directory.systemTemp.createTemp('featured_rev');
    addTearDown(() => dir.delete(recursive: true));
    final cache = File('${dir.path}/featured.cache.json');
    final a = track(title: '遇见', artist: '孙燕姿', durationMs: 210000, songId: 'a');
    final b = track(title: '江南', artist: '林俊杰', durationMs: 267000, songId: 'b');

    final first = FeaturedService(
      library: Library([_FakeOnline([a])]),
      loadSeed: () async => seedJson([seedEntry('遇见', '孙燕姿', durationMs: 210000)]),
      cacheFile: () async => cache,
    );
    await first.prepare();

    final second = FeaturedService(
      library: Library([_FakeOnline([b])]),
      loadSeed: () async => seedJson([seedEntry('江南', '林俊杰', durationMs: 267000)]),
      cacheFile: () async => cache,
    );
    await second.prepare();

    expect(second.tracks.map((t) => t.title), ['江南']);
  });

  test('空种子安全：ready 为 true 且不产生曲目', () async {
    final service = FeaturedService(
      library: Library([_FakeOnline(const [])]),
      loadSeed: () async => seedJson([]),
      cacheFile: () async => null,
    );
    await service.prepare();
    expect(service.ready, isTrue);
    expect(service.isEmpty, isTrue);
    expect(service.payload()['items'], isEmpty);
  });

  test('matchCandidate 供入队兜底映射复用：只给歌名也能挑中，歌手不符则放弃', () {
    final hits = [track(title: '晴天', artist: '周杰伦', durationMs: 269000)];

    final hit = matchCandidate(hits, title: '晴天', artist: '周杰伦', durationMs: 269000);
    expect(hit?.trackKey, hits.single.trackKey);

    // 歌手对不上（同名不同版本）不能凑合
    expect(matchCandidate(hits, title: '晴天', artist: '五月天'), isNull);
    // 歌名对不上
    expect(matchCandidate(hits, title: '花海', artist: '周杰伦'), isNull);
  });
}
