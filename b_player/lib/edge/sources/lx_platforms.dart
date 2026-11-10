import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../music_info.dart';
import '../../l10n/l10n.dart';
import '../../state/lyric_codecs.dart';
import '../music_source.dart';
import 'lx_http.dart';

class LxSearchResult {
  const LxSearchResult({required this.tracks, required this.total});

  final List<Track> tracks;
  final int total;

  static const empty = LxSearchResult(tracks: [], total: 0);
}

/// 单个平台的搜索/歌词适配器；播放地址统一走自定义音源脚本服务。
abstract class LxPlatform {
  const LxPlatform();

  String get id;
  String get label;

  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit});

  Future<MusicLyric> lyric(LxHttp http, Track track);

  Uri? picUri(Track track) {
    final pic = track.extra['pic'];
    if (pic is! String || pic.isEmpty) return null;
    final uri = Uri.tryParse(pic);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') ? uri : null;
  }
}

Track onlineTrack({
  required String platform,
  required String songId,
  required String title,
  required String artist,
  required int durationMs,
  String album = '',
  String pic = '',
  String lrc = '',
  String trc = '',
}) {
  final extra = <String, Object?>{
    'platform': platform,
    'songId': songId,
    if (album.isNotEmpty) 'album': album,
    if (pic.isNotEmpty) 'pic': pic,
    if (lrc.isNotEmpty) 'lrc': lrc,
    if (trc.isNotEmpty) 'trc': trc,
  };
  return Track(
    trackKey: Track.keyFor('$platform:$songId', sourceId: 'lx'),
    sourceId: 'lx',
    title: title,
    artist: artist,
    durationMs: durationMs,
    extra: extra,
  );
}

String joinNames(List<Object?> list, String key) => list
    .map((e) => asMap(e)[key])
    .whereType<String>()
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join('、');

class KgPlatform extends LxPlatform {
  const KgPlatform();

  static const _lyricHeaders = {
    'KG-RC': '1',
    'KG-THash': 'expand_search_manager.cpp:852736169:451',
    'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
  };

  @override
  String get id => 'kg';
  @override
  String get label => '酷狗';

  @override
  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit}) async {
    final body = await http.json(Uri.https('songsearch.kugou.com', '/song_search_v2', {
      'platform': 'AndroidFilter',
      'iscorrection': '1',
      'keyword': keyword,
      'hifiquality': '0',
      'pagesize': '$limit',
      'PrivilegeFilter': '0',
      'page': '$page',
    }));
    if ((body['error_code'] as num?)?.toInt() != 0) {
      throw MusicSourceException(l10n.kugouSearchFailed);
    }
    final data = asMap(body['data']);
    final seen = <String>{};
    final out = <Track>[];
    void add(Object? raw) {
      final m = asMap(raw);
      final hash = (m['FileHash'] as String? ?? '').trim();
      final title = (m['SongName'] as String? ?? '').trim();
      if (hash.isEmpty || title.isEmpty || !seen.add(hash)) return;
      out.add(onlineTrack(
        platform: id,
        songId: hash,
        title: title,
        artist: joinNames(asList(m['Singers']), 'name'),
        durationMs: ((m['Duration'] as num?)?.toInt() ?? 0) * 1000,
        album: (m['AlbumName'] as String? ?? '').trim(),
      ));
    }

    for (final raw in asList(data['lists'])) {
      add(raw);
      for (final group in asList(asMap(raw)['Grp'])) {
        add(group);
      }
    }
    return LxSearchResult(tracks: out, total: (data['total'] as num?)?.toInt() ?? out.length);
  }

  @override
  Future<MusicLyric> lyric(LxHttp http, Track track) async {
    final hash = track.extra['songId'];
    if (hash is! String || hash.isEmpty) throw MusicSourceException(l10n.kugouMissingHash);
    final found = await http.json(
      Uri.https('lyrics.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': track.title,
        'hash': hash,
        'timelength': '${track.durationMs}',
        'lrctxt': '1',
      }),
      headers: _lyricHeaders,
    );
    final candidates = asList(found['candidates']);
    if (candidates.isEmpty) throw MusicSourceException(l10n.kugouNoLyrics);
    final c = asMap(candidates.first);
    final id = c['id']?.toString() ?? '';
    final accessKey = c['accesskey']?.toString() ?? '';
    if (id.isEmpty || accessKey.isEmpty) throw MusicSourceException(l10n.kugouMissingCredential);

    // 优先拿 KRC（逐字）；拿不到或解不出再回退同接口的 LRC。
    try {
      final content = await _download(http, id, accessKey, 'krc');
      final decoded = content == null ? null : decodeKrc(content);
      if (decoded != null && RegExp(r'\[\d+\s*,\s*\d+\]').hasMatch(decoded)) {
        return MusicLyric(
          lyric: decoded,
          format: 'krc',
          name: track.title,
          singer: track.artist,
        );
      }
    } on MusicSourceException {
      // 逐字失败不影响行级歌词，继续往下走。
    }
    final content = await _download(http, id, accessKey, 'lrc');
    if (content == null) throw MusicSourceException(l10n.kugouLyricsEmpty);
    final text = _decodeBase64Text(content);
    if (text.isEmpty) throw MusicSourceException(l10n.kugouLyricsEmpty);
    return MusicLyric(lyric: text, name: track.title, singer: track.artist);
  }

  Future<String?> _download(LxHttp http, String id, String accessKey, String fmt) async {
    final body = await http.json(
      Uri.https('lyrics.kugou.com', '/download', {
        'ver': '1',
        'client': 'pc',
        'id': id,
        'accesskey': accessKey,
        'fmt': fmt,
        'charset': 'utf8',
      }),
      headers: _lyricHeaders,
    );
    final content = body['content'];
    return content is String && content.isNotEmpty ? content : null;
  }
}

class KwPlatform extends LxPlatform {
  const KwPlatform();

  // 酷我歌词接口按 UA 校验，缺失时返回 status 301「音乐查询失败」；必须带上 Referer。
  static const _lyricHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
    'Referer': 'https://m.kuwo.cn/',
  };

  @override
  String get id => 'kw';
  @override
  String get label => '酷我';

  @override
  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit}) async {
    final body = await http.json(Uri.https('search.kuwo.cn', '/r.s', {
      'client': 'kt',
      'all': keyword,
      'pn': '${page - 1}',
      'rn': '$limit',
      'uid': '794762570',
      'ver': 'kwplayer_ar_9.2.2.1',
      'vipver': '1',
      'show_copyright_off': '1',
      'newver': '1',
      'ft': 'music',
      'cluster': '0',
      'strategy': '2012',
      'encoding': 'utf8',
      'rformat': 'json',
      'vermerge': '1',
      'mobi': '1',
      'issubtitle': '1',
    }));
    final total = int.tryParse('${body['TOTAL']}') ?? 0;
    if (total == 0 || '${body['SHOW']}' == '0') {
      throw MusicSourceException(l10n.kuwoSearchFailed);
    }
    final out = <Track>[];
    for (final raw in asList(body['abslist'])) {
      final m = asMap(raw);
      final title = (m['NAME'] as String? ?? '').trim();
      final songId = (m['MUSICRID'] as String? ?? '').replaceFirst('MUSIC_', '').trim();
      if (title.isEmpty || songId.isEmpty) continue;
      out.add(onlineTrack(
        platform: id,
        songId: songId,
        title: title,
        artist: (m['ARTIST'] as String? ?? '').replaceAll('&', '、').trim(),
        durationMs: (int.tryParse('${m['DURATION']}') ?? 0) * 1000,
        album: (m['ALBUM'] as String? ?? '').trim(),
      ));
    }
    return LxSearchResult(tracks: out, total: total);
  }

  @override
  Future<MusicLyric> lyric(LxHttp http, Track track) async {
    // 逐字频道优先；接口不给（部分曲目只有行级歌词）再退回 songinfoandlrc。
    try {
      final word = await _fetchWord(http, track);
      if (word != null) return word;
    } on MusicSourceException {
      // 逐字失败不能连行级歌词一起丢掉。
    }
    // 酷我会概率性返回「音乐查询失败」（HTTP 200 + data null），同一请求重试即可恢复。
    MusicSourceException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _fetchLrc(http, track);
      } on MusicSourceException catch (e) {
        lastError = e;
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw lastError ?? MusicSourceException(l10n.kuwoNoLyrics);
  }

  Future<MusicLyric?> _fetchWord(LxHttp http, Track track) async {
    final id = track.extra['songId'];
    if (id is! String || id.isEmpty) throw MusicSourceException(l10n.kuwoMissingId);
    final bytes = await http.bytes(
      Uri.http('mlyric.kuwo.cn', '/mobi.s', {
        'f': 'web',
        'type': 'lyric',
        'lrcx': '1',
        'rid': id,
        'encode': 'utf8',
      }),
      headers: _lyricHeaders,
    );
    final text = decodeKuwoWord(bytes);
    if (text == null || !RegExp(r'\[kuwo:\s*[0-7]+\]').hasMatch(text)) return null;
    return MusicLyric(
      lyric: text.trim(),
      format: 'kuwo',
      name: track.title,
      singer: track.artist,
    );
  }

  Future<MusicLyric> _fetchLrc(LxHttp http, Track track) async {
    final id = track.extra['songId'];
    if (id is! String || id.isEmpty) throw MusicSourceException(l10n.kuwoMissingId);
    final body = await http.json(
      Uri.https('m.kuwo.cn', '/newh5/singles/songinfoandlrc', {'musicId': id, 'httpsStatus': '1'}),
      headers: _lyricHeaders,
    );
    final lines = <({double at, String text})>[];
    for (final raw in asList(asMap(body['data'])['lrclist'])) {
      final m = asMap(raw);
      final text = (m['lineLyric'] as String? ?? '').trim();
      final at = double.tryParse('${m['time']}');
      if (text.isEmpty || at == null) continue;
      lines.add((at: at, text: text));
    }
    if (lines.isEmpty) throw MusicSourceException(l10n.kuwoNoLyrics);
    lines.sort((a, b) => a.at.compareTo(b.at));
    final out = StringBuffer();
    for (final line in lines) {
      out.writeln('[${_stamp(line.at)}]${line.text}');
    }
    return MusicLyric(lyric: out.toString().trim(), name: track.title, singer: track.artist);
  }
}

class MgPlatform extends LxPlatform {
  const MgPlatform();

  static const _deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const _signSalt = '6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50';
  static const _searchSwitch =
      '{"song":1,"album":0,"singer":0,"tagSong":1,"mvSong":0,"bestShow":1,"songlist":0,"lyricSong":0}';
  static const _mobileUa =
      'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) AppleWebKit/534.30 '
      '(KHTML, like Gecko) Version/4.0 Mobile Safari/534.30';
  static const _lyricHeaders = {
    'Referer': 'https://app.c.nf.migu.cn/',
    'channel': '0146921',
    'User-Agent': _mobileUa,
  };
  // MRC 行首是 `[行起点,行时长]`；Dart 正则不支持 (?m) 内联标志，只能靠 multiLine。
  static final _timedLine = RegExp(r'^[ \t]*\[\d+[ \t]*,[ \t]*\d+\]', multiLine: true);

  @override
  String get id => 'mg';
  @override
  String get label => '咪咕';

  @override
  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit}) async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final sign = md5.convert(utf8.encode('$keyword$_signSalt$_deviceId$ts')).toString();
    final body = await http.json(
      Uri.https('jadeite.migu.cn', '/music_search/v3/search/searchAll', {
        'isCorrect': '0',
        'isCopyright': '1',
        'searchSwitch': _searchSwitch,
        'pageSize': '$limit',
        'text': keyword,
        'pageNo': '$page',
        'sort': '0',
        'sid': 'USS',
      }),
      headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': _deviceId,
        'timestamp': ts,
        'sign': sign,
        'channel': '0146921',
        'User-Agent': _mobileUa,
      },
    );
    if ('${body['code']}' != '000000') {
      final msg = body['info'] is String ? body['info'] as String : l10n.miguSearchFailed;
      throw MusicSourceException(msg);
    }
    final data = asMap(body['songResultData']);
    final out = <Track>[];
    final seen = <String>{};
    for (final group in asList(data['resultList'])) {
      for (final raw in asList(group)) {
        final m = asMap(raw);
        final songId = (m['songId'] as String? ?? '').trim();
        final title = (m['name'] as String? ?? '').trim();
        if (songId.isEmpty || title.isEmpty || !seen.add(songId)) continue;
        var pic = (m['img3'] as String? ?? m['img2'] as String? ?? m['img1'] as String? ?? '').trim();
        if (pic.startsWith('/')) pic = 'https://d.musicapp.migu.cn$pic';
        out.add(onlineTrack(
          platform: id,
          songId: songId,
          title: title,
          artist: joinNames(asList(m['singerList']), 'name'),
          durationMs: ((m['duration'] as num?)?.toInt() ?? 0) * 1000,
          album: (m['album'] as String? ?? '').trim(),
          pic: pic,
          lrc: (m['lrcUrl'] as String? ?? '').trim(),
          trc: (m['trcUrl'] as String? ?? '').trim(),
        ));
      }
    }
    return LxSearchResult(
      tracks: out,
      total: int.tryParse('${data['totalCount']}') ?? out.length,
    );
  }

  @override
  Future<MusicLyric> lyric(LxHttp http, Track track) async {
    // 先用 songId 换 MRC 逐字；没有 MRC 或解码失败再回退检索时带回的 LRC 地址。
    final songId = track.extra['songId'];
    if (songId is String && songId.isNotEmpty) {
      try {
        final word = await _fetchMrc(http, track, songId);
        if (word != null) return word;
      } catch (_) {
        // 逐字链路的任何异常都不该吞掉行级歌词。
      }
    }
    final url = track.extra['lrc'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw MusicSourceException(l10n.miguNoLyricUrl);
    }
    final text = (await http.text(uri, headers: _lyricHeaders)).trim();
    if (text.isEmpty) throw MusicSourceException(l10n.miguLyricsEmpty);
    return MusicLyric(lyric: text, name: track.title, singer: track.artist);
  }

  Future<MusicLyric?> _fetchMrc(LxHttp http, Track track, String songId) async {
    final body = await http.postFormMap(
      Uri.https('c.musicapp.migu.cn', '/MIGUM2.0/v1.0/content/resourceinfo.do', {
        'resourceType': '2',
      }),
      {'resourceId': songId},
      headers: {..._lyricHeaders, 'uiVersion': 'A_music_3.6.1'},
    );
    final resource = asList(body['resource']);
    if (resource.isEmpty) return null;
    final url = (asMap(resource.first)['mrcUrl'] as String? ?? '').trim();
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    final hex = (await http.text(uri, headers: _lyricHeaders)).trim();
    final text = decodeMiguMrc(hex);
    if (text == null || text.trim().isEmpty) return null;
    final format = _timedLine.hasMatch(text) ? 'mrc' : 'lrc';
    return MusicLyric(
      lyric: text.trim(),
      format: format,
      name: track.title,
      singer: track.artist,
    );
  }
}

class TxPlatform extends LxPlatform {
  const TxPlatform();

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';
  static const _searchHeaders = {
    'Referer': 'https://y.qq.com/',
    'Origin': 'https://y.qq.com',
    'User-Agent': _desktopUa,
  };
  // 歌词接口只认播放页来源，缺失会返回 -1310；部分曲目无版权时返回 -1901。
  static const _lyricHeaders = {
    'Referer': 'https://y.qq.com/portal/player.html',
    'User-Agent': _desktopUa,
  };

  @override
  String get id => 'tx';
  @override
  String get label => 'QQ 音乐';

  @override
  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit}) async {
    final body = await http.postJsonMap(
      Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg'),
      {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {
            'num_per_page': limit,
            'page_num': page,
            'query': keyword,
            'search_type': 0,
          },
        },
      },
      headers: _searchHeaders,
    );
    final req = asMap(body['req']);
    if ((req['code'] as num?)?.toInt() != 0) {
      throw MusicSourceException(l10n.qqSearchFailed);
    }
    final data = asMap(req['data']);
    final song = asMap(asMap(data['body'])['song']);
    final meta = asMap(data['meta']);
    final out = <Track>[];
    final seen = <String>{};
    for (final raw in asList(song['list'])) {
      final m = asMap(raw);
      final songId = (m['mid'] as String? ?? '').trim();
      final title = (m['title'] as String? ?? m['name'] as String? ?? '').trim();
      if (songId.isEmpty || title.isEmpty || !seen.add(songId)) continue;
      final album = asMap(m['album']);
      final albumMid = (album['mid'] as String? ?? '').trim();
      out.add(onlineTrack(
        platform: id,
        songId: songId,
        title: title,
        artist: joinNames(asList(m['singer']), 'name'),
        durationMs: ((m['interval'] as num?)?.toInt() ?? 0) * 1000,
        album: (album['name'] as String? ?? '').trim(),
        pic: albumMid.isEmpty ? '' : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg',
      ));
    }
    return LxSearchResult(
      tracks: out,
      total: (meta['sum'] as num?)?.toInt() ?? out.length,
    );
  }

  @override
  Future<MusicLyric> lyric(LxHttp http, Track track) async {
    final songId = track.extra['songId'];
    if (songId is! String || songId.isEmpty) throw MusicSourceException(l10n.qqMissingMid);
    final body = await http.json(
      Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
        'songmid': songId,
        'format': 'json',
        'nobase64': '1',
        'g_tk': '5381',
        'loginUin': '0',
        'hostUin': '0',
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': '0',
        'platform': 'yqq',
        'needNewCode': '0',
      }),
      headers: _lyricHeaders,
    );
    final retcode = (body['retcode'] as num?)?.toInt() ?? (body['code'] as num?)?.toInt() ?? 0;
    if (retcode != 0) throw MusicSourceException(l10n.qqNoLyrics);
    final lyric = body['lyric'];
    if (lyric is! String || lyric.trim().isEmpty) throw MusicSourceException(l10n.qqNoLyrics);
    return MusicLyric(lyric: _unescapeHtml(lyric).trim(), name: track.title, singer: track.artist);
  }
}

class WyPlatform extends LxPlatform {
  const WyPlatform();

  static const _headers = {
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36',
  };

  @override
  String get id => 'wy';
  @override
  String get label => '网易云';

  @override
  Future<LxSearchResult> search(LxHttp http, String keyword, {required int page, required int limit}) async {
    final body = await http.json(
      Uri.https('music.163.com', '/api/search/get', {
        's': keyword,
        'type': '1',
        'limit': '$limit',
        'offset': '${(page - 1) * limit}',
      }),
      headers: _headers,
    );
    final result = asMap(body['result']);
    final out = <Track>[];
    final seen = <String>{};
    for (final raw in asList(result['songs'])) {
      final m = asMap(raw);
      final songId = m['id']?.toString().trim() ?? '';
      final title = (m['name'] as String? ?? '').trim();
      if (songId.isEmpty || title.isEmpty || !seen.add(songId)) continue;
      out.add(onlineTrack(
        platform: id,
        songId: songId,
        title: title,
        artist: joinNames(asList(m['artists']), 'name'),
        durationMs: (m['duration'] as num?)?.toInt() ?? 0,
        album: (asMap(m['album'])['name'] as String? ?? '').trim(),
      ));
    }
    return LxSearchResult(
      tracks: out,
      total: (result['songCount'] as num?)?.toInt() ?? out.length,
    );
  }

  @override
  Future<MusicLyric> lyric(LxHttp http, Track track) async {
    final songId = track.extra['songId'];
    if (songId is! String || songId.isEmpty) throw MusicSourceException(l10n.neteaseMissingId);
    final body = await http.json(
      Uri.https('music.163.com', '/api/song/lyric', {
        'id': songId,
        'lv': '1',
        'kv': '-1',
        'tv': '-1',
        'yv': '1',
      }),
      headers: _headers,
    );
    // YRC 是逐字；没有 YRC 的曲目退回普通 LRC。
    final yrc = asMap(body['yrc'])['lyric'];
    if (yrc is String && RegExp(r'\[\d+\s*,\s*\d+\]').hasMatch(yrc)) {
      return MusicLyric(
        lyric: yrc.trim(),
        format: 'yrc',
        name: track.title,
        singer: track.artist,
      );
    }
    final lyric = asMap(body['lrc'])['lyric'];
    if (lyric is! String || lyric.trim().isEmpty) throw MusicSourceException(l10n.neteaseNoLyrics);
    return MusicLyric(lyric: lyric.trim(), name: track.title, singer: track.artist);
  }
}

/// 按平台 ID 取适配器；顺序遵循 [lxPlatformCatalog]，决定合并时的主音源。
List<LxPlatform> lxPlatformsFor(Iterable<String> ids) {
  final wanted = ids.toSet();
  final selected = [
    for (final platform in const <LxPlatform>[KwPlatform(), KgPlatform(), MgPlatform(), TxPlatform(), WyPlatform()])
      if (wanted.contains(platform.id)) platform,
  ];
  return List.unmodifiable(selected.isEmpty ? const <LxPlatform>[KwPlatform()] : selected);
}

String _stamp(double seconds) {
  final totalMs = (seconds * 1000).round();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(totalMs ~/ 60000)}:${two((totalMs % 60000) ~/ 1000)}.${two((totalMs % 1000) ~/ 10)}';
}

String _decodeBase64Text(String content) {
  try {
    return utf8.decode(base64Decode(content), allowMalformed: true).trim();
  } on FormatException {
    throw MusicSourceException(l10n.lyricsDecodeFailed);
  }
}

/// QQ 音乐的旧歌词接口会把引号等转义成 HTML 实体。
String _unescapeHtml(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ');
