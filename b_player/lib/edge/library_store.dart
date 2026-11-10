import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'music_info.dart';

/// 单个音源的本地索引快照。对应 any-listen 的 `music_library` 缓存表：
/// 启动先读它把曲库立刻显示出来，再在后台做增量扫描。
class LibraryIndex {
  LibraryIndex({
    required this.root,
    required this.tracks,
    required this.broken,
    required this.scannedAtMs,
    required this.tookMs,
  });

  static const version = 1;

  final String root;
  final List<Track> tracks;
  final int broken;
  final int scannedAtMs;
  final int tookMs;

  Map<String, Object?> toJson() => {
        'version': version,
        'root': root,
        'scannedAtMs': scannedAtMs,
        'tookMs': tookMs,
        'broken': broken,
        'tracks': [for (final t in tracks) t.toJson()],
      };

  static LibraryIndex? fromJson(Map<String, Object?> m) {
    if (m['version'] != version) return null;
    final root = m['root'];
    final rawTracks = m['tracks'];
    if (root is! String || rawTracks is! List) return null;
    final tracks = <Track>[];
    for (final raw in rawTracks) {
      if (raw is! Map) continue;
      tracks.add(Track.fromJson(root, raw.cast<String, Object?>()));
    }
    return LibraryIndex(
      root: root,
      tracks: tracks,
      broken: (m['broken'] as num?)?.toInt() ?? 0,
      scannedAtMs: (m['scannedAtMs'] as num?)?.toInt() ?? 0,
      tookMs: (m['tookMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 索引落盘：写临时文件再改名，避免进程被杀时留下半个 JSON。
class LibraryStore {
  LibraryStore(this.directory);

  final String directory;

  File get file => File(p.join(directory, 'library.index.json'));

  Future<LibraryIndex?> read() async {
    try {
      final f = file;
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return null;
      return LibraryIndex.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> write(LibraryIndex index) async {
    await Directory(directory).create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(index.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<void> clear() async {
    try {
      final f = file;
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
