import 'dart:io';

import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../library_scanner.dart';
import '../music_info.dart';
import '../music_source.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';
import 'webdav_store.dart';

class WebDavSyncResult {
  const WebDavSyncResult({
    required this.tracks,
    required this.folders,
    required this.scannedAtMs,
    required this.tookMs,
    this.failedFolders = 0,
    this.canceled = false,
    this.error,
  });

  final List<Track> tracks;
  final int folders;
  final int scannedAtMs;
  final int tookMs;
  final int failedFolders;
  final bool canceled;
  final String? error;
}

/// WebDAV 音源：递归 PROPFIND 把远程音频扫进统一曲库。
///
/// 远程文件不能像本地那样读标签，标题/歌手先从文件名解析；
/// 时长在首次播放时由引擎给出，封面按需下载到本机缓存。
class WebDavSource extends MusicSource {
  WebDavSource({
    required this.server,
    required this.store,
    WebDavClient? client,
  }) : _client = client ?? WebDavClient(server: server);

  final WebDavServer server;
  final WebDavIndexStore store;
  final WebDavClient _client;

  @override
  String get id => server.id;
  @override
  String get kind => 'webdav';
  @override
  String get label => server.displayName;
  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.list,
        MusicSourceCapability.search,
        MusicSourceCapability.audio,
        MusicSourceCapability.lyric,
        MusicSourceCapability.pic,
      };

  static const _concurrency = 4;
  static const _imageExts = {'.jpg', '.jpeg', '.png', '.webp'};
  static const _skippedDirs = {'@eadir', '#recycle', r'$recycle.bin', 'system volume information'};

  List<Track> _tracks = const [];
  final Map<String, Track> _byKey = {};
  final Map<String, File> _artCache = {};
  bool _loaded = false;
  DateTime? _lastSyncAt;
  int _lastTookMs = 0;
  String? _lastError;

  int get trackCount => _tracks.length;
  DateTime? get lastSyncAt => _lastSyncAt;
  int get lastTookMs => _lastTookMs;
  String? get lastError => _lastError;
  String get baseUrl => server.url;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final index = await store.read(id, server.url);
    if (index == null) return;
    _tracks = index.tracks;
    _lastTookMs = index.tookMs;
    _lastError = index.error;
    _lastSyncAt =
        index.scannedAtMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(index.scannedAtMs);
    _reindex();
  }

  Future<WebDavSyncResult> sync({
    void Function(int tracks, int folders)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();
    final base = server.baseUri;
    final pending = <Uri>[base];
    final seenDirs = <String>{_dirKey(base)};
    final seenRel = <String>{};
    final previous = {for (final track in _tracks) track.relPath: track};
    final tracks = <Track>[];
    var folders = 0;
    var failedFolders = 0;
    var canceled = false;
    String? partialError;

    try {
      while (pending.isNotEmpty) {
        if (isCancelled?.call() == true) {
          canceled = true;
          break;
        }
        final batch = pending.take(_concurrency).toList(growable: false);
        pending.removeRange(0, batch.length);
        final listed = await Future.wait(batch.map(_listDir));
        for (final item in listed) {
          folders++;
          final error = item.error;
          if (error != null) {
            if (_samePath(item.dir, base)) throw WebDavException(error);
            failedFolders++;
            partialError ??= error;
            continue;
          }
          final files = <DavEntry>[];
          final images = <String, DavEntry>{};
          for (final entry in item.entries) {
            if (_samePath(entry.uri, item.dir)) continue;
            if (entry.isCollection) {
              if (_skipDir(entry.name)) continue;
              final dir = entry.collectionUri;
              if (seenDirs.add(_dirKey(dir))) pending.add(dir);
              continue;
            }
            files.add(entry);
            final ext = p.extension(entry.name).toLowerCase();
            if (_imageExts.contains(ext)) images[entry.name.toLowerCase()] = entry;
          }
          final lrcs = <String, DavEntry>{
            for (final entry in files)
              if (p.extension(entry.name).toLowerCase() == '.lrc') entry.name.toLowerCase(): entry,
          };
          for (final file in files) {
            final name = file.name;
            if (!LibraryScanner.extensions.contains(p.extension(name).toLowerCase())) continue;
            final rel = _relative(base, file.uri);
            if (rel.isEmpty || !seenRel.add(rel)) continue;
            final stem = p.basenameWithoutExtension(name);
            final prev = previous[rel];
            final sameFile =
                prev != null && prev.size == file.size && prev.modifiedMs == file.modifiedMs;
            final parsed = _parseName(stem);
            final lrc = lrcs['${stem.toLowerCase()}.lrc'];
            final cover = _coverFor(stem, images);
            tracks.add(Track(
              trackKey: Track.keyFor(rel, sourceId: id),
              sourceId: id,
              title: parsed.title,
              artist: parsed.artist,
              durationMs: sameFile ? prev.durationMs : 0,
              relPath: rel,
              absPath: file.uri.toString(),
              lyricRel: lrc?.uri.toString(),
              size: file.size,
              modifiedMs: file.modifiedMs,
              extra: cover == null ? const {} : {'davCover': cover.uri.toString()},
            ));
          }
        }
        onProgress?.call(tracks.length, folders);
      }
    } catch (e) {
      _lastError = '$e';
      rethrow;
    }

    tracks.sort((a, b) => a.relPath.toLowerCase().compareTo(b.relPath.toLowerCase()));
    final tookMs = sw.elapsedMilliseconds;
    final now = DateTime.now();
    final error = failedFolders > 0 ? l10n.webdavPartialFolders(failedFolders) : null;
    if (!canceled) {
      _tracks = List.unmodifiable(tracks);
      _lastSyncAt = now;
      _lastTookMs = tookMs;
      _lastError = error;
      _reindex();
      try {
        await store.write(
          id,
          WebDavIndex(
            base: server.url,
            tracks: _tracks,
            scannedAtMs: now.millisecondsSinceEpoch,
            tookMs: tookMs,
            error: error,
          ),
        );
      } catch (_) {
        // 索引落盘失败不影响本次内存曲库。
      }
    }
    return WebDavSyncResult(
      tracks: tracks,
      folders: folders,
      scannedAtMs: now.millisecondsSinceEpoch,
      tookMs: tookMs,
      failedFolders: failedFolders,
      canceled: canceled,
      error: error,
    );
  }

  Future<({Uri dir, List<DavEntry> entries, String? error})> _listDir(Uri dir) async {
    try {
      return (dir: dir, entries: await _client.list(dir), error: null);
    } catch (e) {
      return (dir: dir, entries: const <DavEntry>[], error: '$e');
    }
  }

  void _reindex() {
    _byKey
      ..clear()
      ..addEntries(_tracks.map((track) => MapEntry(track.trackKey, track)));
  }

  @override
  Future<List<String>> listTrackKeys() async => [for (final track in _tracks) track.trackKey];

  @override
  Future<List<Track>> fetchTracks(List<String> keys) async {
    final out = <Track>[];
    for (final key in keys) {
      final track = _byKey[key];
      if (track != null) out.add(track);
    }
    return out;
  }

  @override
  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) async {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return MusicSearchPage(items: const [], total: 0, page: page, limit: limit);
    final hits = <Track>[
      for (final track in _tracks)
        if (track.title.toLowerCase().contains(q) || track.artist.toLowerCase().contains(q)) track,
    ];
    final offset = (page - 1) * limit;
    final from = offset.clamp(0, hits.length);
    final to = (from + limit).clamp(0, hits.length);
    return MusicSearchPage(items: hits.sublist(from, to), total: hits.length, page: page, limit: limit);
  }

  @override
  Future<Uri> audioUri(Track track) async {
    final uri = Uri.tryParse(track.absPath);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw MusicSourceException(l10n.webdavFileUnavailable(track.relPath));
    }
    return uri;
  }

  @override
  Future<Map<String, String>> audioHeaders(Track track) async => _client.audioHeaders;

  @override
  Future<MusicLyric> lyric(Track track) async {
    final url = track.lyricRel;
    if (url == null || url.isEmpty) throw MusicSourceException(l10n.noLyrics);
    final text = await _client.getText(Uri.parse(url));
    if (text.trim().isEmpty) throw MusicSourceException(l10n.noLyrics);
    return MusicLyric(lyric: text);
  }

  @override
  Future<Uri?> picUri(Track track) async {
    final url = track.extra['davCover'];
    if (url is! String || url.isEmpty) return null;
    final cached = _artCache[url];
    if (cached != null && await cached.exists()) return cached.uri;
    try {
      final bytes = await _client.getBytes(Uri.parse(url));
      if (bytes.isEmpty) return null;
      final file = await store.artFile(id, url, _imageExtension(url));
      await file.writeAsBytes(bytes, flush: true);
      _artCache[url] = file;
      return file.uri;
    } catch (_) {
      return null;
    }
  }

  static String _imageExtension(String url) {
    final ext = p.extension(Uri.parse(url).path).toLowerCase();
    return _imageExts.contains(ext) ? ext : '.img';
  }

  static bool _skipDir(String name) {
    final lower = name.trim().toLowerCase();
    return lower.startsWith('.') || _skippedDirs.contains(lower);
  }

  static bool _samePath(Uri a, Uri b) => _dirKey(a) == _dirKey(b);

  static String _dirKey(Uri uri) {
    final path = uri.path;
    return path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  /// 相对服务器根目录的路径，用 `/` 连接；身份哈希与换端口无关。
  static String _relative(Uri base, Uri uri) {
    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= baseSegments.length) {
      var samePrefix = true;
      for (var i = 0; i < baseSegments.length; i++) {
        if (segments[i] != baseSegments[i]) {
          samePrefix = false;
          break;
        }
      }
      if (samePrefix) return segments.sublist(baseSegments.length).join('/');
    }
    return segments.join('/');
  }

  static ({String title, String artist}) _parseName(String stem) {
    var name = stem.trim();
    name = name.replaceFirst(RegExp(r'^[0-9]{1,3}[\s._\-]+'), '');
    name = name.replaceFirst(RegExp(r'^[_\-]+'), '').trim();
    final dash = name.indexOf(' - ');
    if (dash > 0) {
      return (title: name.substring(dash + 3).trim(), artist: name.substring(0, dash).trim());
    }
    return (title: name, artist: l10n.unknownArtist);
  }

  static DavEntry? _coverFor(String stem, Map<String, DavEntry> images) {
    for (final base in [stem.toLowerCase(), 'cover', 'folder', 'front', 'album']) {
      for (final ext in _imageExts) {
        final entry = images['$base$ext'];
        if (entry != null) return entry;
      }
    }
    return null;
  }

  void dispose() => _client.dispose();
}
