import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import '../log.dart';

/// 出厂默认歌单：把「人读的歌名 + 歌手」在节点上解析成真正的 [Track]。
///
/// 为什么种子不直接当曲目用：
/// - `trackKey` 只是 `platform:songId` 的短哈希（[Track.keyFor]），节点没检索过
///   这首曲目时 [Library.byKey] 查不到，入队必然失败；
/// - 哈希不可逆，光有 key 拿不到 platform/songId，也就解析不出播放地址；
/// - key 依赖平台优先级——同一首歌在不同平台勾选下可能是不同的 key。
///
/// 所以种子里的 `trackKey` 只当「搜到的是不是同一首」的指纹校验，真正的曲目由
/// 本服务用关键词检索得到，并 remember 进曲库，使 C 端点击后能直接入队播放。
/// 解析结果落盘缓存：种子不变就不必每次启动重新检索。
class FeaturedService {
  FeaturedService({
    required this.library,
    Future<String> Function()? loadSeed,
    Future<File?> Function()? cacheFile,
    this.concurrency = 2,
  })  : _loadSeed = loadSeed ?? _defaultSeedLoader,
        _cacheFile = cacheFile ?? _defaultCacheFile;

  static const _assetPath = 'assets/featured/default.json';
  static const _cacheName = 'featured.cache.json';

  /// 检索会扇出多个平台，并发过高容易被上游限流。
  final int concurrency;
  final Library library;
  final Future<String> Function() _loadSeed;
  final Future<File?> Function() _cacheFile;

  final List<Track> _tracks = [];
  final Set<String> _keys = {};
  int _seedTotal = 0;
  int _failed = 0;
  bool _ready = false;
  Future<void>? _inflight;

  /// 已解析成功的曲目，按种子顺序；解析过程中即逐条可见。
  List<Track> get tracks => List.unmodifiable(_tracks);

  /// 全部种子处理完毕（无论成败）。为 false 时 [tracks] 可能还在增长。
  bool get ready => _ready;
  int get seedTotal => _seedTotal;
  int get failed => _failed;
  bool get isEmpty => _tracks.isEmpty;

  /// 给 RPC 用的应答体；字段名与 search 的 items 保持同构，C 端可复用渲染逻辑。
  Map<String, Object?> payload() => {
        'ready': _ready,
        'resolved': _tracks.length,
        'failed': _failed,
        'seed': _seedTotal,
        'items': [
          for (final t in _tracks)
            {
              'trackKey': t.trackKey,
              'title': t.title,
              'artist': t.artist,
              'durationMs': t.durationMs,
              'source': t.sourceId,
            },
        ],
      };

  /// 幂等：启动时调用一次，重复调用共用同一轮解析。
  Future<void> prepare() => _inflight ??= _prepare();

  Future<void> _prepare() async {
    try {
      final seed = _Seed.parse(await _loadSeed());
      _seedTotal = seed.tracks.length;
      if (_seedTotal == 0) return;

      final cached = await _readCache(seed.rev);
      if (cached != null && cached.isNotEmpty) {
        _absorb(cached);
        // 缓存只是数据，曲库还要认这些 key，否则入队照样找不到。
        library.remember(_tracks);
        return;
      }

      await _resolveAll(seed.tracks);
      await _writeCache(seed.rev);
    } catch (e) {
      EnodeLog.e('featured', '解析失败', e);
    } finally {
      _ready = true;
      EnodeLog.i('featured', '就绪 resolved=${_tracks.length} failed=$_failed seed=$_seedTotal');
    }
  }

  Future<void> _resolveAll(List<_SeedTrack> seeds) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= seeds.length) return;
        final track = await _resolveOne(seeds[index]);
        if (track == null) {
          _failed++;
          continue;
        }
        if (_absorb([track])) library.remember([track]);
      }
    }

    final workers = concurrency.clamp(1, 6);
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  /// 先按歌名单搜再退「歌名 + 歌手」：各平台对混合串的切词规则不一致，单搜命中率更高。
  Future<Track?> _resolveOne(_SeedTrack seed) async {
    final queries = <String>[
      seed.title,
      if (seed.artist.isNotEmpty) '${seed.title} ${seed.artist}',
    ];
    for (final query in queries) {
      try {
        final page = await library.searchAsync(
          query,
          limit: 12,
          timeout: const Duration(seconds: 8),
        );
        final hit = matchCandidate(
          page.items,
          trackKey: seed.trackKey,
          title: seed.title,
          artist: seed.artist,
          durationMs: seed.durationMs,
        );
        if (hit != null) return hit;
      } catch (e) {
        EnodeLog.w('featured', '检索失败 q=$query', e);
      }
    }
    return null;
  }

  /// 返回是否有新增（同一 key 只留一份，避免「换一批」出现重复）。
  bool _absorb(Iterable<Track> tracks) {
    var added = false;
    for (final t in tracks) {
      if (t.trackKey.isEmpty || !_keys.add(t.trackKey)) continue;
      _tracks.add(t);
      added = true;
    }
    return added;
  }

  Future<List<Track>?> _readCache(String rev) async {
    try {
      final file = await _cacheFile();
      if (file == null || !await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['rev'] != rev) return null;
      final items = raw['items'];
      if (items is! List) return null;
      return [
        for (final m in items)
          if (m is Map) _trackFromCache(Map<String, Object?>.from(m)),
      ];
    } catch (e) {
      EnodeLog.w('featured', '缓存读取失败', e);
      return null;
    }
  }

  Future<void> _writeCache(String rev) async {
    if (_tracks.isEmpty) return;
    try {
      final file = await _cacheFile();
      if (file == null) return;
      await file.parent.create(recursive: true);
      final body = jsonEncode({
        'v': 1,
        'rev': rev,
        'items': [for (final t in _tracks) t.toJson()],
      });
      // 与曲库索引一致：先写临时文件再改名，避免进程中断留下半个 JSON。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(body);
      await tmp.rename(file.path);
    } catch (e) {
      EnodeLog.w('featured', '缓存写入失败', e);
    }
  }

  /// 在线曲目没有磁盘路径，不走 [Track.fromJson]（那会拼出一个无意义的 absPath）。
  Track _trackFromCache(Map<String, Object?> m) {
    final meta = m['meta'];
    return Track(
      trackKey: m['key'] is String ? m['key'] as String : '',
      title: m['title'] is String ? m['title'] as String : '',
      artist: m['artist'] is String ? m['artist'] as String : '',
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      sourceId: m['source'] is String ? m['source'] as String : 'lx',
      extra: meta is Map ? Map<String, Object?>.from(meta) : const {},
    );
  }

  static Future<String> _defaultSeedLoader() => rootBundle.loadString(_assetPath);

  static Future<File?> _defaultCacheFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, _cacheName));
    } catch (e) {
      EnodeLog.w('featured', '拿不到缓存目录', e);
      return null;
    }
  }
}

/// 从候选里挑出最匹配的一条：指纹全等优先，其次按歌名/歌手/时长打分。
///
/// 歌单解析与「入队兜底映射」共用这一套规则——两处判断必须一致，
/// 否则同一次点歌在解析阶段和入队阶段会选出不同版本。
Track? matchCandidate(
  Iterable<Track> hits, {
  String trackKey = '',
  required String title,
  String artist = '',
  int durationMs = 0,
}) {
  final all = hits.toList(growable: false);
  if (trackKey.isNotEmpty) {
    for (final track in all) {
      if (track.trackKey == trackKey) return track;
    }
  }

  final wantTitle = normalizeForMatch(title);
  if (wantTitle.isEmpty) return null;
  final wantArtist = normalizeForMatch(artist);

  Track? best;
  var bestScore = 0;
  for (final track in all) {
    if (normalizeForMatch(track.title) != wantTitle) continue;
    final hitArtist = normalizeForMatch(track.artist);
    int score;
    if (wantArtist.isEmpty) {
      score = 1;
    } else if (hitArtist == wantArtist) {
      score = 3;
    } else if (hitArtist.isNotEmpty &&
        (hitArtist.contains(wantArtist) || wantArtist.contains(hitArtist))) {
      score = 2;
    } else {
      continue;
    }
    if (durationMs > 0 && track.durationMs > 0) {
      final drift = (track.durationMs - durationMs).abs();
      if (drift <= 5000) {
        score += 2;
      } else if (drift > 20000) {
        // 小时长偏差多半是现场版/翻唱：扣到 0 以下直接排除，
        // 宁可少一首也不要让顾客点《晴天》听成某个 live。
        score -= 3;
      }
    }
    if (score > bestScore) {
      best = track;
      bestScore = score;
    }
  }
  return bestScore > 0 ? best : null;
}

/// 去掉空白与常见标点，让「G.E.M.邓紫棋」和「G.E.M. 邓紫棋」能对上。
String normalizeForMatch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'''[\s\u3000·・.,，。、!！?？'"“”‘’()（）\[\]【】《》<>/\\|+&_~-]+'''), '');

class _SeedTrack {
  const _SeedTrack({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.durationMs,
  });

  final String trackKey;
  final String title;
  final String artist;
  final int durationMs;
}

class _Seed {
  const _Seed(this.rev, this.tracks);

  /// 种子内容的指纹：歌单改了就得重新解析，没改则直接吃缓存。
  final String rev;
  final List<_SeedTrack> tracks;

  static _Seed parse(String text) {
    final raw = jsonDecode(text);
    final list = raw is Map ? raw['tracks'] : null;
    final tracks = <_SeedTrack>[];
    if (list is List) {
      for (final m in list) {
        if (m is! Map) continue;
        final title = (m['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        tracks.add(_SeedTrack(
          trackKey: (m['trackKey'] as String? ?? '').trim(),
          title: title,
          artist: (m['artist'] as String? ?? '').trim(),
          durationMs: _asInt(m['durationMs']),
        ));
      }
    }
    final fingerprint = [
      for (final t in tracks) '${t.trackKey}|${t.title}|${t.artist}|${t.durationMs}',
    ].join('\n');
    final rev = sha256.convert(utf8.encode(fingerprint)).toString().substring(0, 16);
    return _Seed(rev, tracks);
  }

  /// 种子是人手写的，时长可能写成字符串，两种都接受。
  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
