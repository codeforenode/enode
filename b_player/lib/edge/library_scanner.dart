import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import 'music_info.dart';
import '../l10n/l10n.dart';

class ScanResult {
  ScanResult({
    required this.root,
    required this.tracks,
    required this.broken,
    required this.scannedAtMs,
    required this.tookMs,
    this.error,
    this.canceled = false,
  });

  final String root;
  final List<Track> tracks;
  final int broken;
  final int scannedAtMs;
  final int tookMs;
  final String? error;
  final bool canceled;
}

/// 目录扫描：递归找音频文件，读标签/时长，匹配同名 `.lrc`。
/// 元数据解析按块放进 isolate，避免卡住 UI；块之间上报进度。
abstract final class LibraryScanner {
  static const extensions = {
    '.mp3', '.flac', '.m4a', '.mp4', '.ape', '.ogg', '.opus',
    '.wav', '.aif', '.aiff', '.aifc', '.webm', '.mkv',
  };

  static const _chunkSize = 40;

  static Future<ScanResult> scan(
    String root, {
    List<Track>? previous,
    String sourceId = 'local',
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();
    final dir = Directory(root);
    if (!await dir.exists()) {
      return ScanResult(
        root: root,
        tracks: const [],
        broken: 0,
        scannedAtMs: _now(),
        tookMs: sw.elapsedMilliseconds,
        error: l10n.folderMissing(root),
      );
    }

    final files = <File>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (isCancelled?.call() == true) break;
        if (e is File && extensions.contains(p.extension(e.path).toLowerCase())) files.add(e);
      }
    } on FileSystemException catch (e) {
      return ScanResult(
        root: root,
        tracks: const [],
        broken: 0,
        scannedAtMs: _now(),
        tookMs: sw.elapsedMilliseconds,
        error: l10n.folderUnreadable(e.message),
      );
    }

    final prevByRel = {
      for (final t in previous ?? const <Track>[]) t.relPath: t,
    };
    final total = files.length;
    final tracks = <Track>[];
    var done = 0;

    for (var i = 0; i < files.length; i += _chunkSize) {
      if (isCancelled?.call() == true) break;
      final slice = files.sublist(i, (i + _chunkSize).clamp(0, files.length));
      final entries = <Map<String, Object?>>[];
      for (final f in slice) {
        final rel = p.relative(f.path, from: root);
        final prev = prevByRel[rel];
        int size = 0;
        int mtime = 0;
        try {
          final st = f.statSync();
          size = st.size;
          mtime = st.modified.millisecondsSinceEpoch;
        } catch (_) {}
        entries.add({
          'root': root,
          'source': sourceId,
          'rel': rel,
          'size': size,
          'mtime': mtime,
          if (prev != null && prev.size == size && prev.modifiedMs == mtime) ...{
            'title': prev.title,
            'artist': prev.artist,
            'durationMs': prev.durationMs,
          },
        });
      }
      final parsed = await Isolate.run(() => _parseChunk(entries));
      tracks.addAll(parsed);
      done += slice.length;
      onProgress?.call(done, total);
    }

    final canceled = isCancelled?.call() == true;
    final seen = {for (final t in tracks) t.relPath};
    final broken = prevByRel.keys.where((rel) => !seen.contains(rel)).length;

    return ScanResult(
      root: root,
      tracks: tracks..sort((a, b) => a.relPath.toLowerCase().compareTo(b.relPath.toLowerCase())),
      broken: broken,
      scannedAtMs: _now(),
      tookMs: sw.elapsedMilliseconds,
      canceled: canceled,
    );
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}

List<Track> _parseChunk(List<Map<String, Object?>> entries) {
  final lrcIndex = <String, Map<String, String>>{};
  final out = <Track>[];

  Map<String, String> lrcsOf(String dir) => lrcIndex.putIfAbsent(dir, () {
        final map = <String, String>{};
        try {
          for (final e in Directory(dir).listSync(followLinks: false)) {
            if (e is! File) continue;
            final name = p.basename(e.path);
            final ext = p.extension(name).toLowerCase();
            if (ext == '.lrc') map[p.basenameWithoutExtension(name).toLowerCase()] = name;
          }
        } catch (_) {}
        return map;
      });

  for (final e in entries) {
    final root = e['root'] as String;
    final sourceId = e['source'] as String? ?? 'local';
    final rel = e['rel'] as String;
    final abs = p.join(root, rel);
    final size = (e['size'] as num?)?.toInt() ?? 0;
    final mtime = (e['mtime'] as num?)?.toInt() ?? 0;

    final cached = e['title'] as String?;
    var title = cached;
    var artist = e['artist'] as String?;
    var durationMs = (e['durationMs'] as num?)?.toInt();

    if (title == null) {
      try {
        final m = readMetadata(File(abs), getImage: false);
        title = m.title?.trim();
        artist = m.artist?.trim();
        durationMs = m.duration?.inMilliseconds;
      } catch (_) {
        // 标签损坏/格式不支持：退回文件名，不让单个文件拖垮整次扫描。
      }
    }

    var t = title?.trim() ?? '';
    var a = artist?.trim() ?? '';
    if (t.isEmpty) {
      final stem = p.basenameWithoutExtension(rel).trim();
      final dash = stem.indexOf(' - ');
      if (dash > 0) {
        a = a.isEmpty ? stem.substring(0, dash).trim() : a;
        t = stem.substring(dash + 3).trim();
      } else {
        t = stem;
      }
    }
    if (a.isEmpty) a = l10n.unknownArtist;

    final dir = p.dirname(abs);
    final lrc = lrcsOf(dir)[p.basenameWithoutExtension(abs).toLowerCase()];
    out.add(Track(
      trackKey: Track.keyFor(rel, sourceId: sourceId),
      sourceId: sourceId,
      title: t,
      artist: a,
      durationMs: durationMs ?? 0,
      relPath: rel,
      absPath: abs,
      lyricRel: lrc == null ? null : p.join(p.dirname(rel), lrc),
      size: size,
      modifiedMs: mtime,
    ));
  }
  return out;
}
