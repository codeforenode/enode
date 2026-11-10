import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:b_player/edge/library.dart';
import 'package:b_player/edge/sources/lx_http.dart';
import 'package:b_player/edge/sources/lx_online_source.dart';
import 'package:b_player/edge/sources/lx_platforms.dart';
import 'package:b_player/edge/sources/lx_settings.dart';
import 'package:b_player/edge/sources/lx_source_entry.dart';
import 'package:b_player/edge/sources/lx_source_resolver.dart';
import 'package:b_player/l10n/l10n.dart';
import 'package:b_player/state/lrc.dart';

http.Response _json(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _kgSong({
  required String hash,
  required String title,
  required String singer,
  int seconds = 269,
  int album = 0,
}) =>
    {
      'FileHash': hash,
      'SongName': title,
      'Singers': [
        {'name': singer},
      ],
      'Duration': seconds,
      'AlbumName': '专辑$album',
    };

Map<String, Object?> _kwSong({
  required String id,
  required String title,
  required String artist,
  int seconds = 269,
}) =>
    {
      'MUSICRID': 'MUSIC_$id',
      'NAME': title,
      'ARTIST': artist,
      'DURATION': '$seconds',
      'ALBUM': '专辑',
    };

Map<String, Object?> _mgSong({
  required String id,
  required String title,
  required String singer,
  int seconds = 269,
}) =>
    {
      'songId': id,
      'name': title,
      'singerList': [
        {'name': singer},
      ],
      'duration': seconds,
      'img3': '/v3/pic/cover.jpg',
      'lrcUrl': 'https://d.musicapp.migu.cn/lrc/$id.lrc',
      'trcUrl': '',
    };

Map<String, Object?> _txSong({
  required String mid,
  required String title,
  required String singer,
  int seconds = 269,
}) =>
    {
      'mid': mid,
      'title': title,
      'name': title,
      'interval': seconds,
      'singer': [
        {'name': singer},
      ],
      'album': {'name': '专辑', 'mid': 'ALBUM1'},
    };

Map<String, Object?> _wySong({
  required int id,
  required String title,
  required String artist,
  int ms = 269000,
}) =>
    {
      'id': id,
      'name': title,
      'artists': [
        {'name': artist},
      ],
      'duration': ms,
      'album': {'name': '专辑'},
    };

MockClient _searchClient(int Function() onRequest) => MockClient((request) async {      onRequest();
      final host = request.url.host;
      if (host == 'songsearch.kugou.com') {
        return _json({
          'error_code': 0,
          'data': {
            'total': 8,
            'lists': [
              _kgSong(hash: 'KG1', title: '晴天', singer: '周杰伦'),
            ],
          },
        });
      }
      if (host == 'search.kuwo.cn') {
        return _json({
          'TOTAL': '9',
          'SHOW': '1',
          'abslist': [
            _kwSong(id: 'KW1', title: '晴天', artist: '周杰伦'),
          ],
        });
      }
      if (host == 'jadeite.migu.cn') {
        expect(request.headers['sign'], hasLength(32));
        return _json({
          'code': '000000',
          'songResultData': {
            'totalCount': '10',
            'resultList': [
              [_mgSong(id: 'MG1', title: '晴天', singer: '周杰伦')],
            ],
          },
        });
      }
      if (host == 'u.y.qq.com') {
        expect(request.method, 'POST');
        return _json({
          'req': {
            'code': 0,
            'data': {
              'meta': {'sum': 11},
              'body': {
                'song': {
                  'list': [
                    _txSong(mid: 'TX1', title: '晴天', singer: '周杰伦'),
                  ],
                },
              },
            },
          },
        });
      }
      if (host == 'music.163.com') {
        return _json({
          'result': {
            'songCount': 12,
            'songs': [
              _wySong(id: 186016, title: '晴天', artist: '周杰伦'),
            ],
          },
        });
      }
      return http.Response('not found', 404);
    });

final _emptyClient = MockClient((_) async => _json({}));

class _FakeResolver extends LxSourceResolver {
  _FakeResolver({this.accept = const {}, this.failures = const [], this.empty = false});

  final Map<String, String> accept;
  final List<String> failures;
  final bool empty;
  final List<String> calls = [];

  static const _entry = LxSourceEntry(
    id: 'lx_test',
    url: 'https://example.com/source.js',
    script: 'x',
    meta: LxSourceMeta(name: 'stub'),
  );

  @override
  List<LxSourceEntry> get entries => empty ? const [] : const [_entry];

  @override
  List<String> get lastFailures => failures;

  @override
  Future<LxResolvedUrl?> resolve({
    required String platform,
    required Map<String, Object?> musicInfo,
    required String quality,
    Set<String> excluding = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(platform);
    final name = accept[platform];
    if (name == null) return null;
    return LxResolvedUrl(
      sourceId: 'lx_$platform',
      sourceName: name,
      uri: Uri.parse('https://cdn.test/$platform.mp3'),
    );
  }
}

void main() {
  test('在线平台解析：五个平台统一成 Track 并保留平台元数据', () async {
    int calls = 0;
    final source = LxOnlineSource(client: _searchClient(() => calls++));

    final page = await source.search('晴天', limit: 20);

    expect(calls, 5);
    expect(page.items, hasLength(1), reason: '五平台同歌应合并为一条');
    final track = page.items.single;
    expect(track.trackKey, startsWith('lx:'));
    expect(track.sourceId, 'lx');
    expect(track.title, '晴天');
    expect(track.artist, '周杰伦');
    expect(track.durationMs, 269000);
    expect(track.extra['platform'], 'kw', reason: '默认平台顺序 kw/kg/mg/tx/wy');

    final alts = track.extra['alts'] as List;
    expect(alts, hasLength(4));
    expect(
      {for (final alt in alts) (alt as Map)['platform']},
      {'kg', 'mg', 'tx', 'wy'},
    );
    expect(page.total, 50, reason: '上游 total 之和大于合并条数');
  });

  test('检索缓存与并发合并：同关键词只请求一轮平台', () async {
    int calls = 0;
    final source = LxOnlineSource(client: _searchClient(() => calls++));

    final results = await Future.wait([
      source.search('晴天'),
      source.search('晴天'),
      source.search('晴天'),
    ]);
    expect(calls, 5, reason: '五个平台各一次');
    expect(results.map((r) => r.items.single.trackKey).toSet(), hasLength(1));

    await source.search('晴天');
    expect(calls, 5, reason: '60s 内命中缓存');
  });

  test('audioUri：主平台失败后按 alts 回退到能取链的平台', () async {
    final resolver = _FakeResolver(accept: {'kg': 'stub'});
    final source = LxOnlineSource(client: _emptyClient, sourceResolver: resolver);
    final base = onlineTrack(platform: 'kw', songId: 'KW1', title: '晴天', artist: '周杰伦', durationMs: 269000);
    final track = base.withExtra({
      ...base.extra,
      'alts': [
        {'platform': 'kg', 'songId': 'KG1'},
      ],
    });

    final uri = await source.audioUri(track);
    expect(uri.toString(), 'https://cdn.test/kg.mp3');
    expect(resolver.calls, ['kw', 'kg'], reason: '主平台没取到链后回退到备选平台');
  });

  test('audioUri：未导入脚本时不回落任何内置服务', () async {
    final source = LxOnlineSource(client: _emptyClient, sourceResolver: _FakeResolver(empty: true));
    final track = onlineTrack(platform: 'kw', songId: 'KW1', title: 't', artist: 'a', durationMs: 1000);

    await expectLater(
      source.audioUri(track),
      throwsA(isA<MusicSourceException>().having((e) => e.message, 'message', l10n.noImportedScripts)),
    );
  });

  test('能力门控：没有脚本时既不声明检索也不声明取链', () {
    final noScript = LxOnlineSource(client: _emptyClient, sourceResolver: _FakeResolver(empty: true));
    expect(noScript.canResolve, isFalse);
    expect(noScript.supports(MusicSourceCapability.search), isFalse);
    expect(noScript.supports(MusicSourceCapability.audio), isFalse);
    expect(noScript.supports(MusicSourceCapability.lyric), isTrue, reason: '歌词走平台公开接口，不需要脚本');

    final withScript = LxOnlineSource(client: _emptyClient, sourceResolver: _FakeResolver());
    expect(withScript.canResolve, isTrue);
    expect(withScript.supports(MusicSourceCapability.search), isTrue);
    expect(withScript.supports(MusicSourceCapability.audio), isTrue);
  });

  test('Library：没有脚本时在线检索不出结果，也不发请求', () async {
    int calls = 0;
    final online = LxOnlineSource(
      client: _searchClient(() => calls++),
      sourceResolver: _FakeResolver(empty: true),
    );
    final library = Library([online]);
    expect(library.canSearch, isFalse);

    final page = await library.searchAsync('晴天');
    expect(calls, 0, reason: '门控在上游请求之前');
    expect(page.items, isEmpty);
    expect(page.total, 0);
  });

  test('audioUri：所有脚本取链失败时带上原因', () async {
    final resolver = _FakeResolver(failures: ['星海: 上游拒绝']);
    final source = LxOnlineSource(client: _emptyClient, sourceResolver: resolver);
    final track = onlineTrack(platform: 'kw', songId: 'KW1', title: 't', artist: 'a', durationMs: 1000);

    await expectLater(
      source.audioUri(track),
      throwsA(isA<MusicSourceException>()
          .having((e) => e.message, 'message', l10n.sourceResolveFailed('星海: 上游拒绝'))),
    );
  });

  test('歌词：kg 没有 KRC 时回退 base64 LRC', () async {
    final formats = <String?>[];
    final httpClient = MockClient((request) async {
      if (request.url.path == '/search') {
        return _json({
          'candidates': [
            {'id': '123', 'accesskey': 'abc'},
          ],
        });
      }
      expect(request.url.path, '/download');
      final fmt = request.url.queryParameters['fmt'];
      formats.add(fmt);
      return _json({
        'content': fmt == 'krc' ? '' : base64Encode(utf8.encode('[00:01.00]故事的小黄花')),
      });
    });
    final http = LxHttp(httpClient);
    final track = onlineTrack(platform: 'kg', songId: 'KG1', title: '晴天', artist: '周杰伦', durationMs: 269000);

    final lyric = await const KgPlatform().lyric(http, track);
    expect(lyric.lyric, contains('故事的小黄花'));
    expect(lyric.isEmpty, isFalse);
    expect(formats, ['krc', 'lrc'], reason: '逐字优先，拿不到才回退行级');
    expect(lyric.format, 'lrc');
  });

  test('歌词：kg 拿到 KRC 时不再请求 LRC', () async {
    final formats = <String?>[];
    final httpClient = MockClient((request) async {
      if (request.url.path == '/search') {
        return _json({
          'candidates': [
            {'id': '123', 'accesskey': 'abc'},
          ],
        });
      }
      final fmt = request.url.queryParameters['fmt'];
      formats.add(fmt);
      return _json({
        'content': 'AQIDBDjb6kGOA0B3Yb6EHB7jW1mQdtEMhwK1QZW0wbNgT2Bp13NonA==',
      });
    });
    final track = onlineTrack(platform: 'kg', songId: 'KG1', title: '晴天', artist: '周杰伦', durationMs: 269000);

    final lyric = await const KgPlatform().lyric(LxHttp(httpClient), track);
    expect(lyric.format, 'krc');
    expect(formats, ['krc']);
    final lines = parseLyric(lyric.lyric, format: lyric.format);
    expect(lines.single.words, hasLength(2));
  });

  test('歌词：kw 没有逐字频道时回退 lrclist 转 LRC', () async {
    final client = MockClient((request) async {
      expect(request.headers['Referer'], 'https://m.kuwo.cn/');
      expect(request.headers['User-Agent'], contains('Chrome/120'));
      if (request.url.host == 'mlyric.kuwo.cn') {
        expect(request.url.queryParameters['rid'], 'KW1');
        expect(request.url.queryParameters['lrcx'], '1');
        return http.Response.bytes(utf8.encode('音乐查询失败'), 200);
      }
      return _json({
        'data': {
          'lrclist': [
            {'time': '12.34', 'lineLyric': '第二句'},
            {'time': '1.5', 'lineLyric': '第一句'},
          ],
        },
      });
    });
    final track = onlineTrack(platform: 'kw', songId: 'KW1', title: 't', artist: 'a', durationMs: 1000);

    final lyric = await const KwPlatform().lyric(LxHttp(client), track);
    expect(lyric.lyric, '[00:01.50]第一句\n[00:12.34]第二句');
    expect(lyric.format, 'lrc');
  });

  test('歌词：kw 逐字频道可用时直接返回 kuwo 格式', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'mlyric.kuwo.cn');
      return http.Response.bytes(
        base64Decode(
          'VFA9Y29udGVudA0KDQp4nPNMNwl0L48Ki3AtN0l0j6yMMDR1CQsLcg4Ps6gKCgsKinDLcQl3zQkLDquIyCg1L0j3zTKPcg+1BQAK1hKF',
        ),
        200,
      );
    });
    final track = onlineTrack(platform: 'kw', songId: 'KW1', title: 't', artist: 'a', durationMs: 1000);

    final lyric = await const KwPlatform().lyric(LxHttp(client), track);
    expect(lyric.format, 'kuwo');
    final lines = parseLyric(lyric.lyric, format: lyric.format);
    expect(lines.single.words.single.text, '逐字');
  });

  test('歌词：mg 没有 MRC 时直接抓取曲目自带 lrcUrl', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'c.musicapp.migu.cn') {
        expect(request.bodyFields['resourceId'], 'MG1');
        return _json({'resource': []});
      }
      expect(request.url.toString(), 'https://d.musicapp.migu.cn/lrc/MG1.lrc');
      expect(request.headers['Referer'], 'https://app.c.nf.migu.cn/');
      return http.Response.bytes(utf8.encode('[00:01.00]咪咕歌词'), 200);
    });
    final track = onlineTrack(
      platform: 'mg',
      songId: 'MG1',
      title: 't',
      artist: 'a',
      durationMs: 1000,
      lrc: 'https://d.musicapp.migu.cn/lrc/MG1.lrc',
    );

    final lyric = await const MgPlatform().lyric(LxHttp(client), track);
    expect(lyric.lyric, '[00:01.00]咪咕歌词');
  });

  test('LxHttp：5xx 重试后带出服务端 message', () async {
    int calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(
        utf8.encode(jsonEncode({'code': 500, 'message': 'ikun no url'})),
        500,
      );
    });

    await expectLater(
      LxHttp(client).text(Uri.parse('https://api.test/x')),
      throwsA(isA<MusicSourceException>().having((e) => e.message, 'message', contains('ikun no url'))),
    );
    expect(calls, 2, reason: '5xx 重试一次');
  });

  test('Library.searchAsync：本机结果在前，在线结果可回查入队', () async {
    final local = [
      Track(trackKey: 'local:1', title: '晴天', artist: '周杰伦', durationMs: 1000),
      Track(trackKey: 'local:2', title: '晴天之外', artist: '五月天', durationMs: 2000),
      Track(trackKey: 'local:3', title: '稻香', artist: '周杰伦', durationMs: 3000),
    ];
    final online = [
      onlineTrack(platform: 'kw', songId: 'KW1', title: '晴天', artist: '周杰伦', durationMs: 4000),
      onlineTrack(platform: 'kg', songId: 'KG1', title: '晴天 (Live)', artist: '周杰伦', durationMs: 5000),
    ];
    final source = _FakeOnlineSource(online);
    final library = Library([source], tracks: local);

    final page = await library.searchAsync('晴天', limit: 10);
    expect(page.total, 4);
    expect(page.items.map((t) => t.trackKey).take(2), ['local:1', 'local:2']);
    expect(page.items.map((t) => t.trackKey).skip(2), online.map((t) => t.trackKey));

    final cached = library.byKey(online.first.trackKey);
    expect(cached, isNotNull);
    expect(cached!.extra['songId'], 'KW1');
  });

  test('Library.searchAsync：在线音源失败不影响本机结果', () async {
    final local = [
      Track(trackKey: 'local:1', title: '晴天', artist: '周杰伦', durationMs: 1000),
    ];
    final library = Library([_FakeOnlineSource(const [], fail: true)], tracks: local);

    final page = await library.searchAsync('晴天');
    expect(page.total, 1);
    expect(page.items.single.trackKey, 'local:1');
  });

  test('Library：并发歌词请求合并成一次上游调用', () async {
    final track = Track(
      trackKey: 'fake:1',
      sourceId: 'fake-online',
      title: '晴天',
      artist: '周杰伦',
      durationMs: 4000,
    );
    final source = _FakeOnlineSource([track]);
    final library = Library([source]);
    await library.searchAsync('晴天');

    final results = await Future.wait([
      library.lyricFor(track.trackKey),
      library.lyricFor(track.trackKey),
    ]);
    expect(source.lyricCalls, 1, reason: '预热与发布共享同一次请求');
    expect(results.map((l) => l?.lyric).toSet(), hasLength(1));
  });

  test('在线歌词：主平台失败后回退到 alts 平台', () async {
    int kwCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'm.kuwo.cn') {
        kwCalls++;
        return _json({'data': null, 'msg': '音乐查询失败', 'status': 301});
      }
      if (request.url.path == '/search') {
        return _json({
          'candidates': [
            {'id': '456', 'accesskey': 'xyz'},
          ],
        });
      }
      if (request.url.path == '/download') {
        return _json({'content': base64Encode(utf8.encode('[00:02.00]备选平台歌词'))});
      }
      return http.Response('not found', 404);
    });
    final source = LxOnlineSource(client: client);
    final base = onlineTrack(platform: 'kw', songId: 'KW1', title: '晴天', artist: '周杰伦', durationMs: 269000);
    final track = base.withExtra({
      ...base.extra,
      'alts': [
        {'platform': 'kg', 'songId': 'KG1'},
      ],
    });

    final lyric = await source.lyric(track);
    expect(lyric.lyric, contains('备选平台歌词'));
    expect(kwCalls, 2, reason: '酷我业务失败重试一次');
  });

  test('歌词：QQ 音乐返回 LRC 并还原 HTML 实体', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'c.y.qq.com');
      expect(request.headers['Referer'], 'https://y.qq.com/portal/player.html');
      expect(request.url.queryParameters['songmid'], 'TX1');
      return _json({'retcode': 0, 'lyric': '[00:01.00]晴天 &amp; 稻香'});
    });
    final track = onlineTrack(platform: 'tx', songId: 'TX1', title: '晴天', artist: '周杰伦', durationMs: 269000);

    final lyric = await const TxPlatform().lyric(LxHttp(client), track);
    expect(lyric.lyric, '[00:01.00]晴天 & 稻香');
  });

  test('歌词：QQ 音乐受限曲目按没有歌词处理', () async {
    final client = MockClient((_) async => _json({'retcode': -1901}));
    final track = onlineTrack(platform: 'tx', songId: 'TX1', title: 't', artist: 'a', durationMs: 1000);

    await expectLater(
      const TxPlatform().lyric(LxHttp(client), track),
      throwsA(isA<MusicSourceException>().having((e) => e.message, 'message', l10n.qqNoLyrics)),
    );
  });

  test('网易云：检索解析 + LRC 歌词', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/search/get') {
        expect(request.url.queryParameters['s'], '晴天');
        expect(request.url.queryParameters['offset'], '0');
        expect(request.url.queryParameters['limit'], '20');
        return _json({
          'result': {
            'songCount': 2,
            'songs': [_wySong(id: 186016, title: '晴天', artist: '周杰伦')],
          },
        });
      }
      expect(request.url.path, '/api/song/lyric');
      expect(request.url.queryParameters['id'], '186016');
      return _json({
        'lrc': {'lyric': '[00:01.00]网易歌词'},
      });
    });
    const platform = WyPlatform();
    final result = await platform.search(LxHttp(client), '晴天', page: 1, limit: 20);
    final track = result.tracks.single;
    expect(track.extra['platform'], 'wy');
    expect(track.extra['songId'], '186016');
    expect(track.title, '晴天');
    expect(track.artist, '周杰伦');
    expect(track.durationMs, 269000);
    expect(result.total, 2);

    final lyric = await platform.lyric(LxHttp(client), track);
    expect(lyric.lyric, '[00:01.00]网易歌词');
  });

  test('设置热更新：只查启用平台，换配置后清缓存', () async {
    final seen = <String>{};
    final client = MockClient((request) async {
      seen.add(request.url.host);
      switch (request.url.host) {
        case 'search.kuwo.cn':
          return _json({
            'TOTAL': '1',
            'SHOW': '1',
            'abslist': [_kwSong(id: 'KW1', title: '晴天', artist: '周杰伦')],
          });
        case 'u.y.qq.com':
          return _json({
            'req': {
              'code': 0,
              'data': {
                'meta': {'sum': 1},
                'body': {
                  'song': {
                    'list': [_txSong(mid: 'TX1', title: '晴天', singer: '周杰伦')],
                  },
                },
              },
            },
          });
        case 'music.163.com':
          return _json({
            'result': {
              'songCount': 1,
              'songs': [_wySong(id: 186016, title: '晴天', artist: '周杰伦')],
            },
          });
        default:
          return http.Response('not found', 404);
      }
    });
    final source = LxOnlineSource(
      client: client,
      settings: const LxSettings(
        quality: '320k',
        enabledPlatforms: {'kw'},
      ),
    );

    await source.search('晴天');
    expect(seen, {'search.kuwo.cn'});

    source.applySettings(const LxSettings(
      quality: 'flac',
      enabledPlatforms: {'tx', 'wy'},
    ));
    seen.clear();
    await source.search('晴天');

    expect(seen, {'u.y.qq.com', 'music.163.com'}, reason: '换配置后缓存已清空，只请求新启用平台');
    expect(source.quality, 'flac');
    expect(source.enabledPlatformIds, {'tx', 'wy'});
  });

  test('Library：在线曲目也能解析歌词/封面/音源名', () async {
    final track = Track(
      trackKey: 'fake:1',
      sourceId: 'fake-online',
      title: '晴天',
      artist: '周杰伦',
      durationMs: 4000,
    );
    final library = Library([_FakeOnlineSource([track])]);

    await library.searchAsync('晴天');
    final lyric = await library.lyricFor(track.trackKey);
    expect(lyric, isNotNull);
    expect(lyric!.lyric, contains('测试歌词'));
    expect(library.sourceLabelFor(track.trackKey), '测试在线');
  });
}

class _FakeOnlineSource extends MusicSource {
  _FakeOnlineSource(this.tracks, {this.fail = false});

  final List<Track> tracks;
  final bool fail;
  int lyricCalls = 0;

  @override
  String get id => 'fake-online';
  @override
  String get kind => 'online';
  @override
  String get label => '测试在线';
  @override
  Set<MusicSourceCapability> get capabilities =>
      const {MusicSourceCapability.search, MusicSourceCapability.lyric};

  @override
  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) async {
    if (fail) throw const MusicSourceException('在线不可用');
    return MusicSearchPage(items: tracks, total: tracks.length, page: page, limit: limit);
  }

  @override
  Future<MusicLyric> lyric(Track track) async {
    lyricCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return MusicLyric(lyric: '[00:01.00]测试歌词', name: track.title, singer: track.artist);
  }
}
