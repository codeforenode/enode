import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../library_scanner.dart';
import '../library_store.dart';
import '../../l10n/l10n.dart';
import '../music_info.dart';
import '../music_source.dart';

/// 本地目录音源：列表提供者 + 检索/播放/歌词/封面资源，全部在本机完成。
/// 对应 any-listen 的本地列表 + 本地资源分发。
class LocalDirectorySource extends MusicSource {
  LocalDirectorySource({
    required String root,
    required this.store,
    this.id = 'local',
  }) : _root = p.normalize(root);

  final LibraryStore store;

  @override
  final String id;
  @override
  String get kind => 'local';
  @override
  String get label => l10n.localFolder;
  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.list,
        MusicSourceCapability.search,
        MusicSourceCapability.audio,
        MusicSourceCapability.lyric,
        MusicSourceCapability.pic,
      };

  String _root;
  String get root => _root;

  List<Track> _tracks = const [];
  final Map<String, Track> _byKey = {};
  bool _loaded = false;
  int _broken = 0;
  DateTime? _lastScanAt;
  int _lastTookMs = 0;
  String? _lastError;

  int get brokenCount => _broken;
  DateTime? get lastScanAt => _lastScanAt;
  int get lastTookMs => _lastTookMs;
  String? get lastError => _lastError;
  int get trackCount => _tracks.length;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final index = await store.read();
    if (index == null) return;
    if (p.normalize(index.root) != _root) {
      await store.clear();
      return;
    }
    _tracks = index.tracks;
    _broken = index.broken;
    _lastTookMs = index.tookMs;
    _lastScanAt = index.scannedAtMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(index.scannedAtMs);
    _reindex();
  }

  /// 换目录：旧索引属于旧根，直接清掉，等下一次扫描重建。
  Future<void> setRoot(String root) async {
    final next = p.normalize(root.trim());
    if (next.isEmpty || next == _root) return;
    _root = next;
    _tracks = const [];
    _byKey.clear();
    _broken = 0;
    _lastScanAt = null;
    _lastTookMs = 0;
    _lastError = null;
    _loaded = true;
    await store.clear();
  }

  Future<ScanResult> scan({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final result = await LibraryScanner.scan(
      _root,
      previous: _tracks,
      sourceId: id,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    _lastError = result.error;
    if (result.error == null && !result.canceled) {
      _tracks = result.tracks;
      _broken = result.broken;
      _lastScanAt = DateTime.fromMillisecondsSinceEpoch(result.scannedAtMs);
      _lastTookMs = result.tookMs;
      _reindex();
      try {
        await store.write(LibraryIndex(
          root: _root,
          tracks: _tracks,
          broken: _broken,
          scannedAtMs: result.scannedAtMs,
          tookMs: result.tookMs,
        ));
      } catch (_) {
        // 索引落盘失败不影响本次内存曲库。
      }
    }
    return result;
  }

  void _reindex() {
    _byKey
      ..clear()
      ..addEntries(_tracks.map((t) => MapEntry(t.trackKey, t)));
  }

  @override
  Future<List<String>> listTrackKeys() async => [for (final t in _tracks) t.trackKey];

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
      for (final t in _tracks)
        if (t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)) t,
    ];
    final offset = (page - 1) * limit;
    final from = offset.clamp(0, hits.length);
    final to = (from + limit).clamp(0, hits.length);
    return MusicSearchPage(items: hits.sublist(from, to), total: hits.length, page: page, limit: limit);
  }

  @override
  Future<Uri> audioUri(Track track) async {
    final file = File(track.absPath);
    if (!await file.exists()) throw MusicSourceException(l10n.fileMissing(track.relPath));
    return file.uri;
  }

  @override
  Future<MusicLyric> lyric(Track track) async {
    final sidecar = await _readSidecar(track);
    if (sidecar != null) return MusicLyric(lyric: sidecar);

    final path = track.absPath;
    final embedded = await Isolate.run(() => _readEmbeddedLyric(path));
    if (embedded != null) return MusicLyric(lyric: embedded);

    throw MusicSourceException(l10n.noLyrics);
  }

  Future<String?> _readSidecar(Track track) async {
    final path = track.lyricPath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uri?> picUri(Track track) async {
    final dir = p.dirname(track.absPath);
    final stem = p.basenameWithoutExtension(track.absPath);
    for (final base in [stem, 'cover', 'folder', 'front', 'album']) {
      for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
        final file = File(p.join(dir, '$base$ext'));
        if (await file.exists()) return file.uri;
      }
    }
    return null;
  }
}

String? _readEmbeddedLyric(String path) {
  try {
    final metadata = readMetadata(File(path), getImage: false);
    final lyric = metadata.lyrics?.trim();
    return (lyric == null || lyric.isEmpty) ? null : lyric;
  } catch (_) {
    return null;
  }
}
