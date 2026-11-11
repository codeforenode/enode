import 'package:http/http.dart' as http;

import '../music_info.dart';
import '../music_source.dart';
import '../../log.dart';
import 'lx_config.dart';
import 'lx_http.dart';
import 'lx_platforms.dart';
import 'lx_settings.dart';
import '../../l10n/l10n.dart';
import 'lx_source_entry.dart';
import 'lx_source_resolver.dart';

/// 在线曲库音源：搜索/歌词走平台公开接口，播放地址只由用户导入的音源脚本兑换。
///
/// 与 any-listen 的分层一致：检索结果是统一 [Track]，曲目自带平台标识，
/// 解析播放地址/歌词时先回本音源，平台失败时按 `alts` 逐个回退。
/// 取链顺序：按导入顺序尝试勾选的脚本，不在项目内内置任何兜底音源。
class LxOnlineSource extends MusicSource {
  LxOnlineSource({
    http.Client? client,
    String? quality,
    List<LxPlatform>? platforms,
    LxSettings? settings,
    LxSourceResolver? sourceResolver,
  })  : _http = LxHttp(client ?? http.Client()),
        _quality = quality ?? settings?.quality ?? lxDefaultQuality,
        _platforms = platforms ??
            lxPlatformsFor(settings?.enabledPlatforms ?? lxDefaultPlatformIds),
        _resolver = sourceResolver;

  static const _cacheTtl = Duration(seconds: 60);
  static const _cacheCapacity = 64;

  final LxHttp _http;
  String _quality;
  List<LxPlatform> _platforms;
  final LxSourceResolver? _resolver;

  String get quality => _quality;
  List<LxPlatform> get platforms => List.unmodifiable(_platforms);
  Set<String> get enabledPlatformIds => {for (final p in _platforms) p.id};
  LxSourceResolver? get resolver => _resolver;

  /// 多音源列表热更新：顺序与勾选状态由 [LxSourceResolver] 维护。
  void applySources(Iterable<LxSourceEntry> sources) {
    _resolver?.setEntries(sources);
    clearCache();
  }

  /// 运行时切换配置：重建平台列表并丢弃旧缓存，避免不同平台结果串味。
  void applySettings(LxSettings settings) {
    _quality = settings.quality;
    _platforms = lxPlatformsFor(settings.enabledPlatforms);
    clearCache();
  }

  final Map<String, ({DateTime at, MusicSearchPage page})> _cache = {};
  final Map<String, Future<MusicSearchPage>> _inflight = {};

  @override
  String get id => 'lx';
  @override
  String get kind => 'online';
  @override
  String get label => l10n.onlineLibrary;
  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.search,
        MusicSourceCapability.audio,
        MusicSourceCapability.lyric,
        MusicSourceCapability.pic,
      };

  /// 是否已导入至少一个可用音源脚本。
  bool get canResolve => _resolver?.entries.isNotEmpty ?? false;

  /// 检索与取链同源：没有脚本时连检索结果都不给。
  /// 否则顾客会搜到一批点了播不出的歌——any-listen 用同一张插件注册表，天然没有这个缺口。
  @override
  bool supports(MusicSourceCapability capability) => switch (capability) {
        MusicSourceCapability.search || MusicSourceCapability.audio => canResolve,
        _ => super.supports(capability),
      };

  /// 同一关键词的并发检索合并成一次上游请求，避免按键触发请求风暴。
  @override
  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) {
    final q = keyword.trim();
    if (q.isEmpty) {
      return Future.value(MusicSearchPage(items: const [], total: 0, page: page, limit: limit));
    }
    final key = '$q|$page|$limit';
    final cached = _cache[key];
    if (cached != null) {
      if (DateTime.now().difference(cached.at) <= _cacheTtl) return Future.value(cached.page);
      _cache.remove(key);
    }
    final running = _inflight[key];
    if (running != null) return running;

    final future = _searchAll(q, page, limit);
    _inflight[key] = future;
    return future.whenComplete(() {
      _inflight.remove(key);
    }).then((pageResult) {
      _putCache(key, pageResult);
      return pageResult;
    });
  }

  Future<MusicSearchPage> _searchAll(String q, int page, int limit) async {
    final results = await Future.wait(_platforms.map((platform) async {
      try {
        return await platform.search(_http, q, page: page, limit: limit).timeout(lxSearchTimeout);
      } catch (_) {
        // 单平台失败只损失该平台结果，不影响其它平台。
        return LxSearchResult.empty;
      }
    }));

    final all = <Track>[];
    var upstreamTotal = 0;
    for (final result in results) {
      all.addAll(result.tracks);
      upstreamTotal += result.total;
    }
    final merged = _merge(all);
    return MusicSearchPage(
      items: merged,
      total: upstreamTotal > merged.length ? upstreamTotal : merged.length,
      page: page,
      limit: limit,
    );
  }

  /// 同歌名+歌手+时长（±3s）视为同一首，只保留首条并记录平台备选。
  List<Track> _merge(List<Track> all) {
    final groups = <String, List<Track>>{};
    for (final track in all) {
      final key = '${track.title.trim().toLowerCase()}\u0000${track.artist.trim().toLowerCase()}';
      final bucket = groups.putIfAbsent(key, () => []);
      var matched = false;
      for (var i = 0; i < bucket.length; i++) {
        if ((bucket[i].durationMs - track.durationMs).abs() <= 3000) {
          bucket[i] = _appendAlt(bucket[i], track);
          matched = true;
          break;
        }
      }
      if (!matched) bucket.add(track);
    }
    return [for (final bucket in groups.values) ...bucket];
  }

  Track _appendAlt(Track primary, Track other) {
    final platform = other.extra['platform'];
    final songId = other.extra['songId'];
    if (platform is! String || songId == null) return primary;
    final alts = <Map<String, Object?>>[
      for (final alt in asList(primary.extra['alts']))
        if (alt is Map) Map<String, Object?>.from(alt),
    ];
    if (alts.any((alt) => alt['platform'] == platform && alt['songId'] == songId)) return primary;
    alts.add({
      'platform': platform,
      'songId': songId,
      if (other.extra['lrc'] is String) 'lrc': other.extra['lrc'],
    });
    return primary.withExtra({...primary.extra, 'alts': alts});
  }

  void _putCache(String key, MusicSearchPage page) {
    if (_cache.length >= _cacheCapacity) {
      String? oldestKey;
      DateTime? oldest;
      for (final entry in _cache.entries) {
        if (oldest == null || entry.value.at.isBefore(oldest)) {
          oldest = entry.value.at;
          oldestKey = entry.key;
        }
      }
      if (oldestKey != null) _cache.remove(oldestKey);
    }
    _cache[key] = (at: DateTime.now(), page: page);
  }

  /// 清空检索缓存；索引重建或测试时调用。
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  @override
  Future<Uri> audioUri(Track track) async {
    final attempts = <Map<String, Object?>>[];
    final platform = track.extra['platform'];
    final songId = track.extra['songId'];
    if (platform is String && songId != null) {
      attempts.add({'platform': platform, 'songId': songId});
    }
    for (final alt in asList(track.extra['alts'])) {
      if (alt is Map) attempts.add(Map<String, Object?>.from(alt));
    }
    if (attempts.isEmpty) throw MusicSourceException(l10n.trackNoPlatform);

    // 主平台 + alts：逐个试，日志里记清每个平台的耗时和失败原因，
    // 这样「这首歌为什么放不出来」不用猜。
    final id = EnodeLog.shortId(track.trackKey);
    final total = attempts.where((a) => a['platform'] is String && a['songId'] != null).length;
    var index = 0;
    MusicSourceException? lastError;
    for (final attempt in attempts) {
      final p = attempt['platform'];
      final sid = attempt['songId'];
      if (p is! String || sid == null) continue;
      index++;
      final watch = Stopwatch()..start();
      try {
        final uri = await _resolveUrl(p, sid.toString(), track);
        EnodeLog.i(
          'source',
          '$id [$index/$total] $p 成功 ${watch.elapsedMilliseconds}ms ${uri.scheme}://${uri.host}',
        );
        return uri;
      } on MusicSourceException catch (e) {
        lastError = e;
        EnodeLog.w('source', '$id [$index/$total] $p 失败 ${watch.elapsedMilliseconds}ms', e);
      } catch (e) {
        lastError = MusicSourceException(l10n.resolveFailed('$e'));
        EnodeLog.w('source', '$id [$index/$total] $p 异常 ${watch.elapsedMilliseconds}ms', e);
      }
    }
    EnodeLog.e('source', '$id 全部 $total 个平台都取不到链');
    throw lastError ?? MusicSourceException(l10n.resolveFailedShort);
  }

  /// 取链只走用户导入的脚本：按顺序逐个尝试，全部失败则报错，不回落内置服务。
  Future<Uri> _resolveUrl(String platform, String songId, Track track) async {
    final resolver = _resolver;
    if (resolver == null || resolver.entries.isEmpty) {
      throw MusicSourceException(l10n.noImportedScripts);
    }
    final resolved = await resolver.resolve(
      platform: platform,
      musicInfo: buildLxMusicInfo(
        platform: platform,
        songId: songId,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
        album: track.extra['album'] is String ? track.extra['album'] as String : '',
      ),
      quality: _quality,
      timeout: lxUrlTimeout,
    );
    if (resolved != null) return resolved.uri;
    final failures = resolver.lastFailures;
    throw MusicSourceException(
      failures.isEmpty ? l10n.noUsableScripts : l10n.sourceResolveFailed(failures.join('；')),
    );
  }

  /// 主平台歌词失败时按 `alts` 里的其它平台逐个尝试，和播放地址的回退链一致。
  @override
  Future<MusicLyric> lyric(Track track) async {
    final id = EnodeLog.shortId(track.trackKey);
    MusicSourceException? lastError;
    var index = 0;
    for (final candidate in _lyricCandidates(track)) {
      final platform = _platformById(candidate.extra['platform']);
      if (platform == null) continue;
      index++;
      final watch = Stopwatch()..start();
      try {
        final lyric = await platform.lyric(_http, candidate);
        if (!lyric.isEmpty) {
          EnodeLog.i(
            'lyric',
            '$id 平台 ${platform.id} 取到 ${lyric.lyric.length} 字符 '
            '${lyric.format} ${watch.elapsedMilliseconds}ms',
          );
          return lyric;
        }
        lastError = MusicSourceException(l10n.lyricsEmpty);
        EnodeLog.w('lyric', '$id 平台 ${platform.id} 返回空歌词 ${watch.elapsedMilliseconds}ms');
      } on MusicSourceException catch (e) {
        lastError = e;
        EnodeLog.w('lyric', '$id 平台 ${platform.id} 取词失败 ${watch.elapsedMilliseconds}ms', e);
      } catch (e) {
        lastError = MusicSourceException(l10n.lyricsFetchFailed('$e'));
        EnodeLog.w('lyric', '$id 平台 ${platform.id} 取词异常 ${watch.elapsedMilliseconds}ms', e);
      }
    }
    EnodeLog.w('lyric', '$id 试过 $index 个平台都没有歌词');
    throw lastError ?? MusicSourceException(l10n.trackNoLyrics);
  }

  Iterable<Track> _lyricCandidates(Track track) sync* {
    yield track;
    for (final alt in asList(track.extra['alts'])) {
      if (alt is! Map) continue;
      final platform = alt['platform'];
      final songId = alt['songId'];
      if (platform is! String || songId == null) continue;
      yield track.withExtra({
        ...track.extra,
        'platform': platform,
        'songId': songId,
        if (alt['lrc'] is String) 'lrc': alt['lrc'],
      });
    }
  }

  @override
  Future<Uri?> picUri(Track track) async {
    final platform = _platformById(track.extra['platform']);
    final pic = platform?.picUri(track) ?? _uriOf(track.extra['pic']);
    return pic;
  }

  LxPlatform? _platformById(Object? id) {
    for (final platform in _platforms) {
      if (platform.id == id) return platform;
    }
    return null;
  }

  static Uri? _uriOf(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') ? uri : null;
  }
}
