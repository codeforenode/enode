import 'music_info.dart';
import 'music_source.dart';
import '../l10n/l10n.dart';
import '../log.dart';

export 'music_info.dart';
export 'music_source.dart';

/// 本机统一曲库：所有音源的曲目汇到这里，队列/检索/歌词只认 [Track.trackKey]。
///
/// 播放地址、歌词、封面都按「曲目自带音源优先、其余音源回退」解析，
/// 和 any-listen 的 `getMusicUrl/getLyricInfo` 分发方式一致。
class Library {
  Library(Iterable<MusicSource> sources, {List<Track>? tracks})
      : registry = MusicSourceRegistry(sources) {
    if (tracks != null) replaceTracks(tracks);
  }

  factory Library.demo([int n = 5000]) {
    final tracks = demoTracks(n);
    return Library([StaticSource(tracks: tracks, demoLyrics: true)], tracks: tracks);
  }

  static const _onlineTrackCapacity = 2000;

  /// 在线直链有时效（上游通常 20–30 分钟），缓存只留 3 分钟。
  ///
  /// 入队时的那次取链只是「探测这首能不能播」，顾客前面可能还排着好几首；等轮到
  /// 他时缓存早已不该再用。留 3 分钟足够覆盖「搜到就点」的即时场景，又不会让排队的歌
  /// 拿着快过期的直链去开。
  static const _audioTtl = Duration(minutes: 3);

  final MusicSourceRegistry registry;

  List<Track> _tracks = const [];
  final Map<String, Track> _byKey = {};
  final Map<String, Track> _onlineTracks = {};
  final Map<String, MusicLyric?> _lyricCache = {};
  final Map<String, ({AudioRef ref, DateTime at})> _audioCache = {};
  final Map<String, Future<MusicLyric?>> _lyricInflight = {};
  final Map<String, Future<AudioRef?>> _audioInflight = {};

  List<Track> get tracks => _tracks;

  /// 能不能给出「点了就能播」的检索结果：本机有索引，或有可取链的在线音源。
  bool get canSearch =>
      _tracks.isNotEmpty ||
      registry.sources.any((s) =>
          s.supports(MusicSourceCapability.search) && !s.supports(MusicSourceCapability.list));

  Track? byKey(String key) => _byKey[key] ?? _onlineTracks[key];

  /// 记住检索返回的在线曲目，使之后按 trackKey 入队/解析歌词时仍能找到它。
  /// 在线结果不进 [tracks]，曲库计数始终只反映本机索引。
  void remember(Iterable<Track> tracks) {
    for (final track in tracks) {
      _onlineTracks.remove(track.trackKey);
      _onlineTracks[track.trackKey] = track;
    }
    while (_onlineTracks.length > _onlineTrackCapacity) {
      _onlineTracks.remove(_onlineTracks.keys.first);
    }
  }

  /// 从所有列表型音源重新汇总。索引读盘/扫描完成后调用。
  Future<void> reload() async {
    final all = <Track>[];
    for (final source in registry.sources) {
      if (!source.supports(MusicSourceCapability.list)) continue;
      try {
        await source.load();
        final keys = await source.listTrackKeys();
        all.addAll(await source.fetchTracks(keys));
      } catch (_) {
        // 单个音源不可用不影响其它音源；错误由音源自身记录并展示。
      }
    }
    replaceTracks(all);
  }

  void replaceTracks(Iterable<Track> tracks) {
    _tracks = List.unmodifiable(tracks);
    _byKey
      ..clear()
      ..addEntries(_tracks.map((t) => MapEntry(t.trackKey, t)));
    _lyricCache.clear();
    _audioCache.clear();
  }

  List<Track> _localHits(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final t in _tracks)
        if (t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)) t,
    ];
  }

  ({List<Track> items, int total}) search(String query, {int offset = 0, int limit = 20}) {
    final hits = _localHits(query);
    final from = offset.clamp(0, hits.length);
    final to = (from + limit).clamp(0, hits.length);
    return (items: hits.sublist(from, to), total: hits.length);
  }

  /// 本机索引 + 在线音源合并检索：本机结果在前，在线结果随后分页。
  ///
  /// 只有「非列表型」的音源会被在线查询——列表型音源（本地目录、以后的网盘）
  /// 已经全部进了 [_tracks]，再查一次会重复。
  Future<({List<Track> items, int total})> searchAsync(
    String query, {
    int offset = 0,
    int limit = 20,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final q = query.trim();
    if (q.isEmpty) return (items: const <Track>[], total: 0);
    final local = _localHits(q);
    final from = offset.clamp(0, local.length);
    final to = limit <= 0 ? from : (from + limit).clamp(0, local.length);
    final items = [...local.sublist(from, to)];
    var total = local.length;

    final onlineStart = offset > local.length ? offset - local.length : 0;
    final page = limit <= 0 ? 1 : onlineStart ~/ limit + 1;
    final skip = limit <= 0 ? 0 : onlineStart % limit;
    final sources = [
      for (final s in registry.sources)
        if (s.supports(MusicSourceCapability.search) && !s.supports(MusicSourceCapability.list)) s,
    ];

    final pages = await Future.wait(sources.map((source) async {
      try {
        return await source.search(q, page: page, limit: limit).timeout(timeout);
      } catch (_) {
        // 在线音源不可用只损失该源结果，本机检索照常返回。
        return null;
      }
    }));

    for (final pageResult in pages) {
      if (pageResult == null) continue;
      total += pageResult.total;
      remember(pageResult.items);
      if (items.length >= limit) continue;
      final take = skip < pageResult.items.length
          ? pageResult.items.skip(skip).take(limit - items.length)
          : const <Track>[];
      items.addAll(take);
    }
    return (items: items, total: total);
  }

  /// 同一曲目的并发解析合并成一次，避免「预热 + 发布」同时打同一个上游接口。
  Future<MusicLyric?> lyricFor(String trackKey) {
    final id = EnodeLog.shortId(trackKey);
    if (_lyricCache.containsKey(trackKey)) {
      EnodeLog.d('lyric', '$id 命中缓存');
      return Future.value(_lyricCache[trackKey]);
    }
    final running = _lyricInflight[trackKey];
    if (running != null) {
      EnodeLog.d('lyric', '$id 合并到进行中的取词');
      return running;
    }
    final watch = Stopwatch()..start();
    final future = _resolve(trackKey, MusicSourceCapability.lyric, (source, track) async {
      final lyric = await source.lyric(track);
      if (lyric.isEmpty) throw MusicSourceException(l10n.lyricsEmpty);
      return lyric;
    }, store: (value) => _lyricCache[trackKey] = value);
    _lyricInflight[trackKey] = future;
    return future.then((lyric) {
      watch.stop();
      if (lyric == null) {
        EnodeLog.w('lyric', '$id 取词失败 ${watch.elapsedMilliseconds}ms');
      } else {
        EnodeLog.i(
          'lyric',
          '$id 取词成功 ${lyric.lyric.length} 字符 format=${lyric.format} ${watch.elapsedMilliseconds}ms',
        );
      }
      return lyric;
    }).whenComplete(() => _lyricInflight.remove(trackKey));
  }

  /// 解析播放地址与请求头。[refresh] 丢弃缓存强制重新取链；失败结果不写缓存，
  /// 这样补导入音源脚本后同一首可以立刻再试。
  Future<AudioRef?> audioFor(String trackKey, {bool refresh = false}) {
    final id = EnodeLog.shortId(trackKey);
    if (refresh) {
      _audioCache.remove(trackKey);
      EnodeLog.i('audio', '$id 强制重取直链');
    } else {
      final cached = _audioCache[trackKey];
      if (cached != null) {
        final age = DateTime.now().difference(cached.at);
        if (age <= _audioTtl) {
          EnodeLog.d('audio', '$id 命中缓存 age=${age.inSeconds}s');
          return Future.value(cached.ref);
        }
        EnodeLog.i(
          'audio',
          '$id 缓存过期 age=${age.inMinutes}m（阈值 ${_audioTtl.inMinutes}m），重新取链',
        );
        _audioCache.remove(trackKey);
      }
    }
    final running = _audioInflight[trackKey];
    if (running != null) {
      EnodeLog.d('audio', '$id 合并到进行中的取链');
      return running;
    }
    final watch = Stopwatch()..start();
    final future = _resolve(
      trackKey,
      MusicSourceCapability.audio,
      (source, track) async => AudioRef(
        await source.audioUri(track),
        await source.audioHeaders(track),
      ),
      store: (value) {
        if (value != null) _audioCache[trackKey] = (ref: value, at: DateTime.now());
      },
    );
    _audioInflight[trackKey] = future;
    return future.then((ref) {
      watch.stop();
      if (ref == null) {
        EnodeLog.w('audio', '$id 取链失败 ${watch.elapsedMilliseconds}ms');
      } else {
        EnodeLog.i(
          'audio',
          '$id 取链成功 ${watch.elapsedMilliseconds}ms ${ref.uri.scheme}://${ref.uri.host}',
        );
      }
      return ref;
    }).whenComplete(() => _audioInflight.remove(trackKey));
  }

  Future<Uri?> audioUriFor(String trackKey, {bool refresh = false}) =>
      audioFor(trackKey, refresh: refresh).then((ref) => ref?.uri);

  /// 直链失效（引擎打不开/看门狗超时）时丢掉这一条，下次重新取链。
  void invalidateAudio(String trackKey) => _audioCache.remove(trackKey);

  /// 换音质或换音源后旧直链全部作废。
  void clearAudioCache() => _audioCache.clear();

  Future<Uri?> picUriFor(String trackKey) async {
    final track = byKey(trackKey);
    if (track == null) return null;
    final tried = <String>{};
    while (true) {
      final source = registry.resolve(MusicSourceCapability.pic, preferred: track.sourceId, excluding: tried);
      if (source == null) return null;
      try {
        final uri = await source.picUri(track);
        if (uri != null) return uri;
      } catch (_) {}
      tried.add(source.id);
    }
  }

  String sourceLabelFor(String trackKey) {
    final t = byKey(trackKey);
    if (t == null) return '';
    return registry.byId(t.sourceId)?.label ?? t.sourceId;
  }

  Future<T?> _resolve<T>(
    String trackKey,
    MusicSourceCapability capability,
    Future<T> Function(MusicSource source, Track track) call, {
    required void Function(T? value) store,
  }) async {
    final track = byKey(trackKey);
    if (track == null) return null;
    final tried = <String>{};
    while (true) {
      final source = registry.resolve(capability, preferred: track.sourceId, excluding: tried);
      if (source == null) break;
      try {
        final value = await call(source, track);
        store(value);
        return value;
      } catch (_) {
        tried.add(source.id);
      }
    }
    store(null);
    return null;
  }
}
