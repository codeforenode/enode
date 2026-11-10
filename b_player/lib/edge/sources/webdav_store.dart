import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../music_info.dart';

/// 一个 WebDAV 服务器的曲目索引。远程曲目没有本地根目录，
/// [Track.absPath] 直接存绝对 URL，所以不能复用 LibraryIndex 的按根拼接。
class WebDavIndex {
  const WebDavIndex({
    required this.base,
    required this.tracks,
    required this.scannedAtMs,
    required this.tookMs,
    this.error,
  });

  static const version = 1;

  final String base;
  final List<Track> tracks;
  final int scannedAtMs;
  final int tookMs;
  final String? error;

  Map<String, Object?> toJson() => {
        'version': version,
        'base': base,
        'scannedAtMs': scannedAtMs,
        'tookMs': tookMs,
        'error': ?error,
        'tracks': [for (final track in tracks) _trackToJson(track)],
      };

  static WebDavIndex? fromJson(Object? raw, String expectedBase) {
    if (raw is! Map) return null;
    if (raw['version'] != version) return null;
    final base = raw['base'];
    if (base is! String || base != expectedBase) return null;
    final rawTracks = raw['tracks'];
    if (rawTracks is! List) return null;
    return WebDavIndex(
      base: base,
      tracks: [
        for (final item in rawTracks)
          if (item is Map) _trackFromJson(item.cast<String, Object?>()),
      ],
      scannedAtMs: (raw['scannedAtMs'] as num?)?.toInt() ?? 0,
      tookMs: (raw['tookMs'] as num?)?.toInt() ?? 0,
      error: raw['error'] is String ? raw['error'] as String : null,
    );
  }

  static Map<String, Object?> _trackToJson(Track track) => {
        'key': track.trackKey,
        'source': track.sourceId,
        'rel': track.relPath,
        'title': track.title,
        'artist': track.artist,
        'durationMs': track.durationMs,
        'lyric': ?track.lyricRel,
        'size': track.size,
        'mtime': track.modifiedMs,
        'abs': track.absPath,
        if (track.extra.isNotEmpty) 'extra': track.extra,
      };

  static Track _trackFromJson(Map<String, Object?> m) {
    final rel = m['rel'] is String ? m['rel'] as String : '';
    final source = m['source'] is String ? m['source'] as String : '';
    return Track(
      trackKey: m['key'] is String ? m['key'] as String : Track.keyFor(rel, sourceId: source),
      sourceId: source,
      title: m['title'] is String ? m['title'] as String : '',
      artist: m['artist'] is String ? m['artist'] as String : '',
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      relPath: rel,
      absPath: m['abs'] is String ? m['abs'] as String : '',
      lyricRel: m['lyric'] is String ? m['lyric'] as String : null,
      size: (m['size'] as num?)?.toInt() ?? 0,
      modifiedMs: (m['mtime'] as num?)?.toInt() ?? 0,
      extra: m['extra'] is Map ? Map<String, Object?>.from(m['extra'] as Map) : const {},
    );
  }
}

/// 每个服务器一份索引、一个封面缓存目录；删除服务器时一起清掉。
class WebDavIndexStore {
  WebDavIndexStore(this.directory);

  final String directory;

  File indexFile(String id) => File(p.join(directory, '$id.json'));

  Directory artDir(String id) => Directory(p.join(directory, 'art', id));

  Future<WebDavIndex?> read(String id, String base) async {
    try {
      final file = indexFile(id);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return WebDavIndex.fromJson(decoded, base);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String id, WebDavIndex index) async {
    await Directory(directory).create(recursive: true);
    final file = indexFile(id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(index.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  /// 封面落盘名按 URL 哈希，同一张图不会反复下载。
  Future<File> artFile(String id, String url, String extension) async {
    final digest = sha256.convert(utf8.encode(url)).toString().substring(0, 24);
    final dir = artDir(id);
    await dir.create(recursive: true);
    return File(p.join(dir.path, '$digest$extension'));
  }

  Future<void> clear(String id) async {
    try {
      final file = indexFile(id);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      final dir = artDir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
