import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 统一的曲目模型，对应 any-listen 的 `MusicInfo`：
/// 无论本地目录还是 WebDAV/在线音源，队列、检索、歌词都用同一套字段。
class Track {
  Track({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.sourceId = 'local',
    this.relPath = '',
    this.absPath = '',
    this.lyricRel,
    this.size = 0,
    this.modifiedMs = 0,
    this.extra = const {},
  });

  final String trackKey;
  final String title;
  final String artist;
  final int durationMs;

  /// 产生这条曲目的音源 id；解析播放地址/歌词时先回到这个音源。
  final String sourceId;

  /// 音源内的相对路径；换根目录后 trackKey 不变。
  final String relPath;
  final String absPath;
  final String? lyricRel;
  final int size;
  final int modifiedMs;

  /// 在线音源的平台私有元数据（平台、歌曲 ID、封面、歌词地址等）；
  /// 对应 any-listen 在线 `MusicInfo.meta`，本地曲目为空。
  final Map<String, Object?> extra;

  bool get isLocal => sourceId == 'local';
  bool get hasLyric => lyricRel != null;

  /// 在线音源归并同一首歌时补写平台备选，其它字段保持不变。
  Track withExtra(Map<String, Object?> extra) => Track(
        trackKey: trackKey,
        title: title,
        artist: artist,
        durationMs: durationMs,
        sourceId: sourceId,
        relPath: relPath,
        absPath: absPath,
        lyricRel: lyricRel,
        size: size,
        modifiedMs: modifiedMs,
        extra: extra,
      );

  String? get lyricPath {
    final lyric = lyricRel;
    return lyric == null ? null : p.join(p.dirname(absPath), p.basename(lyric));
  }

  Map<String, Object?> toJson() {
    final lyric = lyricRel;
    return {
      'key': trackKey,
      'source': sourceId,
      'rel': relPath,
      'title': title,
      'artist': artist,
      'durationMs': durationMs,
      'lyric': ?lyric,
      'size': size,
      'mtime': modifiedMs,
      if (extra.isNotEmpty) 'meta': extra,
    };
  }

  static Track fromJson(String root, Map<String, Object?> m) {
    final rel = m['rel'] is String ? m['rel'] as String : '';
    final source = m['source'] is String ? m['source'] as String : 'local';
    return Track(
      trackKey: m['key'] is String ? m['key'] as String : keyFor(rel, sourceId: source),
      sourceId: source,
      title: m['title'] is String ? m['title'] as String : '',
      artist: m['artist'] is String ? m['artist'] as String : '',
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      relPath: rel,
      absPath: p.join(root, rel),
      lyricRel: m['lyric'] is String ? m['lyric'] as String : null,
      size: (m['size'] as num?)?.toInt() ?? 0,
      modifiedMs: (m['mtime'] as num?)?.toInt() ?? 0,
      extra: m['meta'] is Map ? Map<String, Object?>.from(m['meta'] as Map) : const {},
    );
  }

  /// 音源内路径的短哈希：同目录改名/换根目录都不变；移动目录会变。
  static String keyFor(String identity, {String sourceId = 'local'}) =>
      '$sourceId:${sha256.convert(identity.toLowerCase().codeUnits).toString().substring(0, 12)}';
}

/// 对应 any-listen 的 `LyricInfo`：主歌词必填，翻译/罗马音/逐字歌词按需扩展。
class MusicLyric {
  const MusicLyric({
    required this.lyric,
    this.tlyric,
    this.rlyric,
    this.awlyric,
    this.name = '',
    this.singer = '',
    this.interval,
    this.format = 'lrc',
  });

  final String lyric;
  final String? tlyric;
  final String? rlyric;
  final String? awlyric;
  final String name;
  final String singer;
  final String? interval;

  /// [lyric] 的格式：lrc / yrc / krc / qrc / mrc / kuwo / awlrc。
  final String format;

  bool get isEmpty => lyric.trim().isEmpty;
}
