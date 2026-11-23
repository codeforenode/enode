import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../atomic_json.dart';
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
      final decoded = await AtomicJsonFile(indexFile(id)).read();
      return WebDavIndex.fromJson(decoded, base);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String id, WebDavIndex index) async {
    await AtomicJsonFile(indexFile(id)).write(index.toJson());
  }

  /// 封面落盘名按 URL 哈希，同一张图不会反复下载。
  static String artName(String url, String extension) {
    final digest = sha256.convert(utf8.encode(url)).toString().substring(0, 24);
    return '$digest$extension';
  }

  Future<File> artFile(String id, String url, String extension) async {
    final dir = artDir(id);
    await dir.create(recursive: true);
    return File(p.join(dir.path, artName(url, extension)));
  }

  /// 单台服务器的封面缓存预算；超出后按最久未用（mtime）先删。
  static const artBudgetBytes = 200 * 1024 * 1024;

  /// 同步完成后调用：清掉已不在曲库里的封面，再把总量压到 [maxBytes] 以内。
  ///
  /// [keepNames] 用 [artName] 生成。封面是纯缓存，删错了下次播放会重下，
  /// 所以这里只按预算兜底，不做精确的引用计数。
  Future<void> pruneArt(
    String id,
    Set<String> keepNames, {
    int maxBytes = artBudgetBytes,
  }) async {
    final dir = artDir(id);
    if (!await dir.exists()) return;
    final kept = <({File file, int size, DateTime modified})>[];
    try {
      await for (final item in dir.list()) {
        if (item is! File) continue;
        if (!keepNames.contains(p.basename(item.path))) {
          try {
            await item.delete();
          } catch (_) {}
          continue;
        }
        try {
          final stat = await item.stat();
          kept.add((file: item, size: stat.size, modified: stat.modified));
        } catch (_) {}
      }
    } catch (_) {
      return;
    }
    var total = kept.fold<int>(0, (sum, item) => sum + item.size);
    if (total <= maxBytes) return;
    kept.sort((a, b) => a.modified.compareTo(b.modified));
    for (final item in kept) {
      if (total <= maxBytes) break;
      try {
        await item.file.delete();
        total -= item.size;
      } catch (_) {}
    }
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
