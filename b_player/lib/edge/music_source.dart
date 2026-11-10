import 'dart:math';

import 'music_info.dart';
import '../l10n/l10n.dart';

enum MusicSourceCapability { list, search, audio, lyric, pic }

class MusicSearchPage {
  const MusicSearchPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<Track> items;
  final int total;
  final int page;
  final int limit;
}

class MusicSourceException implements Exception {
  const MusicSourceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 播放地址 + 该地址需要的请求头。凭据不拼进 URL，避免写进日志或错误提示。
class AudioRef {
  AudioRef(this.uri, [Map<String, String> headers = const {}])
      : headers = Map.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
}

/// 可插拔音源，对应 any-listen 的扩展能力：
///
/// * 列表提供者：`listTrackKeys / fetchTracks / parseMetadata`
/// * 资源提供者：`search / audioUri / lyric / picUri`
///
/// 本地目录是 [MusicSourceCapability.list] + 全部资源能力；
/// 之后的 WebDAV/网盘只用新增一个实现，检索、入队、歌词链路不变。
abstract class MusicSource {
  String get id;
  String get kind;
  String get label;
  Set<MusicSourceCapability> get capabilities;

  /// 读取索引/初始化；重复调用应幂等。
  Future<void> load() async {}

  bool supports(MusicSourceCapability capability) => capabilities.contains(capability);

  // ---------------- 列表提供者 ----------------

  Future<List<String>> listTrackKeys() async => const [];

  Future<List<Track>> fetchTracks(List<String> keys) async => const [];

  /// 延迟解析元数据（WebDAV 等远程源的 `unparsed` 项）。
  Future<Track> parseMetadata(Track track) async => track;

  // ---------------- 资源提供者 ----------------

  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) =>
      throw MusicSourceException(l10n.unsupportedSearch);

  Future<Uri> audioUri(Track track) => throw MusicSourceException(l10n.unsupportedPlay);

  /// WebDAV 等需要认证的源在这里给请求头；普通直链返回空。
  Future<Map<String, String>> audioHeaders(Track track) async => const {};

  Future<MusicLyric> lyric(Track track) => throw MusicSourceException(l10n.unsupportedLyrics);

  Future<Uri?> picUri(Track track) async => null;
}

/// 按能力解析音源，对应 any-listen 的 `getExtSource(action, excludeList, preferSource)`：
/// 先试曲目自带的音源，失败后在同一能力的其它音源间回退。
class MusicSourceRegistry {
  MusicSourceRegistry([Iterable<MusicSource> sources = const []]) : _sources = [...sources];

  final List<MusicSource> _sources;

  List<MusicSource> get sources => List.unmodifiable(_sources);

  MusicSource? byId(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 同 id 的源视为替换（编辑后重建），顺序保持不变。
  void add(MusicSource source) {
    final index = _sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = source;
    } else {
      _sources.add(source);
    }
  }

  MusicSource? remove(String id) {
    final index = _sources.indexWhere((s) => s.id == id);
    return index < 0 ? null : _sources.removeAt(index);
  }

  Iterable<MusicSource> supporting(MusicSourceCapability capability) =>
      _sources.where((s) => s.supports(capability));

  MusicSource? resolve(
    MusicSourceCapability capability, {
    String? preferred,
    Set<String> excluding = const {},
  }) {
    if (preferred != null && !excluding.contains(preferred)) {
      final p = byId(preferred);
      if (p != null && p.supports(capability)) return p;
    }
    for (final s in _sources) {
      if (!s.supports(capability) || excluding.contains(s.id)) continue;
      return s;
    }
    return null;
  }
}

/// 演示/测试用音源：曲目全部在内存里，歌词是确定性占位内容。
/// 正式运行不会用到（正式曲库由 `LocalDirectorySource` 提供）。
class StaticSource extends MusicSource {
  StaticSource({
    required List<Track> tracks,
    this.demoLyrics = false,
    this.id = 'local',
  }) : _tracks = List.unmodifiable(tracks);

  final List<Track> _tracks;
  final bool demoLyrics;

  @override
  final String id;
  @override
  String get label => l10n.demoLibrary;
  @override
  String get kind => 'memory';
  @override
  Set<MusicSourceCapability> get capabilities => const {
        MusicSourceCapability.list,
        MusicSourceCapability.search,
        MusicSourceCapability.audio,
        MusicSourceCapability.lyric,
      };

  @override
  Future<List<String>> listTrackKeys() async => [for (final t in _tracks) t.trackKey];

  @override
  Future<List<Track>> fetchTracks(List<String> keys) async => _tracks;

  @override
  Future<MusicSearchPage> search(String keyword, {int page = 1, int limit = 20}) async {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return MusicSearchPage(items: const [], total: 0, page: page, limit: limit);
    final hits = [
      for (final t in _tracks)
        if (t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)) t,
    ];
    final offset = (page - 1) * limit;
    final from = offset.clamp(0, hits.length);
    final to = (from + limit).clamp(0, hits.length);
    return MusicSearchPage(items: hits.sublist(from, to), total: hits.length, page: page, limit: limit);
  }

  /// 演示模式没有真实音频，给一个占位地址让「入队前置解析」照常通过。
  @override
  Future<Uri> audioUri(Track track) async => Uri.parse('demo://${track.trackKey}');

  @override
  Future<MusicLyric> lyric(Track track) async {
    if (!demoLyrics) throw MusicSourceException(l10n.demoNoLyrics);
    return MusicLyric(lyric: _demoLrc(track));
  }
}

List<Track> demoTracks([int n = 5000]) {
  const heads = ['夜曲', '晴天', '稻香', '半岛', '退后', '安静', '彩虹', '搁浅', '蒲公英', '轨迹', '枫', '海上', '兰亭', '烟花', '千里', '红尘', '青花', '天涯', '方圆', '烟花易'];
  const tails = ['之外', '继续', '满', '冷', '行', '里', '下', '的事', '的雪', '的地方'];
  const artists = ['五月天', '邓紫棋', '朴树', '陈奕迅', '林俊杰', '周杰伦', '李荣浩', '毛不易', '薛之谦', '许嵩'];
  final rnd = Random(n);
  final out = <Track>[];
  for (var i = 0; i < n; i++) {
    final title = heads[i % heads.length] + tails[(i ~/ heads.length) % tails.length] +
        (i >= heads.length * tails.length ? ' $i' : '');
    out.add(Track(
      trackKey: 'local:${i.toString().padLeft(5, '0')}',
      title: title,
      artist: artists[i % artists.length],
      durationMs: 100000 + rnd.nextInt(160000),
    ));
  }
  return out;
}

String _demoLrc(Track t) {
  final b = StringBuffer()
    ..writeln('[ti:${t.title}]')
    ..writeln('[ar:${t.artist}]')
    ..writeln('[00:00.00]${t.title} - ${t.artist}');
  var i = 1;
  for (var ms = 8000; ms < t.durationMs - 2000; ms += 8000) {
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    b.writeln('[$m:$s.00]（演示歌词 $i）');
    i++;
  }
  return b.toString();
}
