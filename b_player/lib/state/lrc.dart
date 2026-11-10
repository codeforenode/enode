/// 歌词时间轴：行 + 逐字。
///
/// 平台格式各异（YRC/KRC/QRC/MRC/Kuwo/AWLRC），这里统一成同一结构：
/// 行有起止时间，行内每个字有起止时间。纯 LRC 只有行，[LyricLine.words] 为空。
typedef LyricWord = ({int startMs, int endMs, String text});

typedef LyricLine = ({int startMs, int endMs, String text, List<LyricWord> words});

typedef _Draft = ({int startMs, int durationMs, String text, List<LyricWord> words});

const List<LyricWord> _noWords = <LyricWord>[];

final RegExp _lrcTag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final RegExp _offsetTag = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
final RegExp _inlineTag = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
final RegExp _lineHeader = RegExp(r'^\[(\d+)\s*,\s*(\d+)\]\s*(.*)$');
final RegExp _parenWord = RegExp(r'\((\d+)\s*,\s*(\d+)(?:\s*,\s*-?\d+)?\)');
final RegExp _angleWord = RegExp(r'<(-?\d+)\s*,\s*(-?\d+)(?:\s*,\s*-?\d+)?>');
final RegExp _kuwoTag = RegExp(r'\[kuwo:([^\]]+)\]');
final RegExp _enhancedTag = RegExp(r'^\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]');

/// 按格式解析；未知格式先嗅探内容，再回退标准 LRC。
List<LyricLine> parseLyric(String raw, {String format = 'lrc'}) {
  final kind = switch (format.trim().toLowerCase().replaceAll('.', '')) {
    'yrc' || 'word' => 'yrc',
    'krc' => 'krc',
    'qrc' => 'qrc',
    'mrc' => 'mrc',
    'kuwo' || 'kw' => 'kuwo',
    'awlrc' || 'aw' => 'awlrc',
    _ => _sniff(raw),
  };
  return switch (kind) {
    'yrc' => parseYrc(raw),
    'krc' => parseKrc(raw),
    'qrc' => parseQrc(raw),
    'mrc' => parseMrc(raw),
    'kuwo' => parseKuwo(raw),
    'awlrc' => parseAwlrc(raw),
    _ => parseLrc(raw),
  };
}

String _sniff(String raw) {
  if (_kuwoTag.hasMatch(raw) && _angleWord.hasMatch(raw)) return 'kuwo';
  final first = raw
      .split('\n')
      .map((row) => row.trim())
      .firstWhere((row) => row.isNotEmpty, orElse: () => '');
  if (_lineHeader.hasMatch(first)) {
    return first.contains('<') && !first.contains('(') ? 'krc' : 'yrc';
  }
  if (_enhancedTag.hasMatch(first)) {
    return _inlineTag.hasMatch(first) && !_angleWord.hasMatch(first) ? 'lrc' : 'awlrc';
  }
  return 'lrc';
}

/// 标准 LRC；带 `<mm:ss.xx>` 行内标签的增强 LRC 会解析出逐字时间。
List<LyricLine> parseLrc(String raw) {
  final offset = _readOffset(raw);
  final drafts = <_Draft>[];
  for (final row in raw.split('\n')) {
    final tags = _lrcTag.allMatches(row).toList();
    if (tags.isEmpty) continue;
    final body = row.replaceAll(_lrcTag, '').trim();
    if (body.isEmpty) continue;
    final plain = _stripInline(body);
    for (final tag in tags) {
      final start = _tagToMs(tag.group(1)!, tag.group(2)!, tag.group(3));
      if (start == null) continue;
      drafts.add((
        startMs: start,
        durationMs: 0,
        text: plain,
        words: _inlineWords(body, start),
      ));
    }
  }
  return _finish(drafts, offset);
}

/// 网易云 YRC：`[行起点,行时长](字起点,字时长,0)字...`，字时间是绝对毫秒。
List<LyricLine> parseYrc(String raw) => _parseHeadered(raw, absoluteWords: true);

/// 酷狗 KRC（解密后）：`[行起点,行时长]<字偏移,字时长,0>字...`，偏移相对行首。
List<LyricLine> parseKrc(String raw) => _parseHeadered(raw, absoluteWords: false);

List<LyricLine> _parseHeadered(String raw, {required bool absoluteWords}) {
  final offset = _readOffset(raw);
  final drafts = <_Draft>[];
  for (final row in raw.split('\n')) {
    final head = _lineHeader.firstMatch(row.trim());
    if (head == null) continue;
    final start = int.tryParse(head.group(1)!);
    final duration = int.tryParse(head.group(2)!);
    if (start == null || duration == null) continue;
    final body = head.group(3)!;
    final marker = absoluteWords ? _parenWord : _angleWord;
    final words = _textAfterMarker(body, marker, (a, _) => absoluteWords ? a : start + a);
    drafts.add((
      startMs: start,
      durationMs: duration,
      text: _stripMarkers(body, marker),
      words: words,
    ));
  }
  return _finish(drafts, offset);
}

/// QQ QRC：`[行起点,行时长]字(字起点,字时长)字(字起点,字时长)`，字时间是绝对毫秒。
List<LyricLine> parseQrc(String raw) {
  final offset = _readOffset(raw);
  final drafts = <_Draft>[];
  for (final row in raw.split('\n')) {
    final head = _lineHeader.firstMatch(row.trim());
    if (head == null) continue;
    final start = int.tryParse(head.group(1)!);
    final duration = int.tryParse(head.group(2)!);
    if (start == null || duration == null) continue;
    final body = head.group(3)!;
    drafts.add((
      startMs: start,
      durationMs: duration,
      text: _stripMarkers(body, _parenWord),
      words: _textBeforeMarker(body, _parenWord, (a, _) => a),
    ));
  }
  return _finish(drafts, offset);
}

/// 咪咕 MRC（TEA 解密后）：`[行起点,行时长]字(字起点,字时长)字...`。
/// 和 YRC/KRC 相反，标记跟在文字后面，形状与 QRC 一致。
List<LyricLine> parseMrc(String raw) => parseQrc(raw);

/// LX 逐字歌词（AWLRC）：`[mm:ss.xx]字<字偏移,字时长>字...`，偏移相对行首。
List<LyricLine> parseAwlrc(String raw) {
  final offset = _readOffset(raw);
  final drafts = <_Draft>[];
  for (final row in raw.split('\n')) {
    final tag = _lrcTag.firstMatch(row);
    if (tag == null) continue;
    final start = _tagToMs(tag.group(1)!, tag.group(2)!, tag.group(3));
    if (start == null) continue;
    final body = row.substring(tag.end);
    final words = _textBeforeMarker(body, _angleWord, (a, _) => start + a);
    drafts.add((
      startMs: start,
      durationMs: 0,
      text: _stripMarkers(body, _angleWord),
      words: words,
    ));
  }
  return _finish(drafts, offset);
}

/// 酷我逐字：行首 `[kuwo:八进制基数]`，字标记 `<a,b,?>` 在文字之前
/// 起点 = |(a+b)/2/d1|、终点 = 起点 + |(a-b)/2/d2|，均相对行首。
List<LyricLine> parseKuwo(String raw) {
  final offset = _readOffset(raw);
  final tag = _kuwoTag.firstMatch(raw);
  var firstDivisor = 1;
  var secondDivisor = 1;
  if (tag != null) {
    final value = int.tryParse(tag.group(1)!.split(']').first.trim(), radix: 8);
    if (value == null) return const [];
    firstDivisor = value ~/ 10;
    secondDivisor = value % 10;
    if (firstDivisor <= 0 || secondDivisor <= 0) return const [];
  }

  final drafts = <_Draft>[];
  for (final row in raw.split('\n')) {
    final line = _lrcTag.firstMatch(row);
    if (line == null) continue;
    final lineStart = _tagToMs(line.group(1)!, line.group(2)!, line.group(3));
    if (lineStart == null) continue;
    final body = row.substring(line.end).trimRight();
    final words = <LyricWord>[];
    var textStart = 0;
    int? wordStart;
    int? wordEnd;
    void flush(int textEnd) {
      if (wordStart == null || wordEnd == null) return;
      final text = body.substring(textStart, textEnd);
      if (text.isNotEmpty) {
        words.add((
          startMs: lineStart + wordStart,
          endMs: lineStart + wordEnd,
          text: text,
        ));
      }
    }

    for (final marker in _angleWord.allMatches(body)) {
      flush(marker.start);
      final a = int.tryParse(marker.group(1)!);
      final b = int.tryParse(marker.group(2)!);
      if (a == null || b == null) {
        wordStart = null;
        wordEnd = null;
        textStart = marker.end;
        continue;
      }
      final relStart = ((a + b) ~/ (firstDivisor * 2)).abs();
      wordStart = relStart;
      wordEnd = relStart + ((a - b) ~/ (secondDivisor * 2)).abs();
      textStart = marker.end;
    }
    flush(body.length);
    if (words.isEmpty) {
      final text = _stripMarkers(body, _angleWord);
      if (text.isNotEmpty) {
        drafts.add((startMs: lineStart, durationMs: 0, text: text, words: _noWords));
      }
      continue;
    }
    drafts.add((
      startMs: lineStart,
      durationMs: 0,
      text: _stripMarkers(body, _angleWord),
      words: words,
    ));
  }
  return _finish(drafts, offset);
}

/// 统一收尾：排序、去重、补行尾、（必要时）补字尾。
List<LyricLine> _finish(List<_Draft> drafts, int offset) {
  final cleaned = <_Draft>[];
  for (final draft in drafts) {
    final start = draft.startMs - offset;
    if (start < 0) continue;
    final words = <LyricWord>[];
    for (final word in draft.words) {
      final ws = word.startMs - offset;
      final we = word.endMs - offset;
      if (ws < 0 && we <= 0) continue;
      words.add((
        startMs: ws < 0 ? 0 : ws,
        endMs: we <= ws ? 0 : we,
        text: word.text,
      ));
    }
    words.sort((a, b) => a.startMs.compareTo(b.startMs));
    var text = draft.text.trim();
    if (text.isEmpty) text = words.map((word) => word.text).join().trim();
    if (text.isEmpty) continue;
    cleaned.add((startMs: start, durationMs: draft.durationMs, text: text, words: words));
  }
  cleaned.sort((a, b) => a.startMs.compareTo(b.startMs));

  final lines = <LyricLine>[];
  for (var i = 0; i < cleaned.length; i++) {
    final draft = cleaned[i];
    final next = i + 1 < cleaned.length ? cleaned[i + 1].startMs : null;
    var end = draft.durationMs > 0 ? draft.startMs + draft.durationMs : (next ?? 0);
    if (next != null && (end <= draft.startMs || end > next)) end = next;
    final words = _fixWords(draft.words, draft.startMs, end);
    if (end <= draft.startMs) {
      end = words.isNotEmpty && words.last.endMs > draft.startMs ? words.last.endMs : draft.startMs + 4000;
    }
    if (lines.isNotEmpty && lines.last.startMs == draft.startMs && lines.last.text == draft.text) continue;
    lines.add((startMs: draft.startMs, endMs: end, text: draft.text, words: words));
  }
  return List.unmodifiable(lines);
}

List<LyricWord> _fixWords(List<LyricWord> raw, int lineStart, int lineEnd) {
  final hasLineEnd = lineEnd > lineStart;
  final words = <LyricWord>[];
  for (var i = 0; i < raw.length; i++) {
    final word = raw[i];
    if (word.text.isEmpty) continue;
    final start = word.startMs < lineStart ? lineStart : word.startMs;
    var end = word.endMs;
    if (end <= start) {
      final next = i + 1 < raw.length ? raw[i + 1].startMs : 0;
      if (next > start) {
        end = next;
      } else if (i > 0) {
        // 末尾字的时长缺失：沿用前一个字的步进，别把最后一个字拖到下一句。
        final previous = raw[i - 1].endMs - raw[i - 1].startMs;
        end = start + (previous > 0 ? previous : 600);
      } else {
        end = hasLineEnd ? lineEnd : start + 600;
      }
    }
    final next = i + 1 < raw.length ? raw[i + 1].startMs : 0;
    if (next > start && next < end) end = next;
    if (hasLineEnd && end > lineEnd) end = lineEnd;
    words.add((startMs: start, endMs: end, text: word.text));
  }
  return List.unmodifiable(words);
}

/// 标记在前：`(ts,dur)文字`，用于 YRC/MRC/KRC。
List<LyricWord> _textAfterMarker(String body, RegExp marker, int Function(int a, int b) startOf) {
  final matches = marker.allMatches(body).toList();
  final words = <LyricWord>[];
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final ts = int.tryParse(match.group(1)!);
    final dur = int.tryParse(match.group(2)!);
    if (ts == null || dur == null) continue;
    final text = body.substring(match.end, i + 1 < matches.length ? matches[i + 1].start : body.length);
    if (text.isEmpty) continue;
    final start = startOf(ts, dur);
    words.add((startMs: start, endMs: dur > 0 ? start + dur : 0, text: text));
  }
  return words;
}

/// 标记在后：`文字(ts,dur)`，用于 QRC/AWLRC。末尾无标记的文字挂到最后一个字。
List<LyricWord> _textBeforeMarker(String body, RegExp marker, int Function(int a, int b) startOf) {
  final matches = marker.allMatches(body).toList();
  final words = <LyricWord>[];
  var textStart = 0;
  for (final match in matches) {
    final text = body.substring(textStart, match.start);
    textStart = match.end;
    final ts = int.tryParse(match.group(1)!);
    final dur = int.tryParse(match.group(2)!);
    if (text.isEmpty || ts == null || dur == null) continue;
    final start = startOf(ts, dur);
    words.add((startMs: start, endMs: dur > 0 ? start + dur : 0, text: text));
  }
  if (textStart < body.length && words.isNotEmpty) {
    final tail = body.substring(textStart);
    if (tail.isNotEmpty) {
      final last = words.removeLast();
      words.add((startMs: last.startMs, endMs: last.endMs, text: last.text + tail));
    }
  }
  return words;
}

List<LyricWord> _inlineWords(String body, int lineStart) {
  final matches = _inlineTag.allMatches(body).toList();
  if (matches.isEmpty) return _noWords;
  final words = <LyricWord>[];
  final lead = body.substring(0, matches.first.start).trim();
  if (lead.isNotEmpty) words.add((startMs: lineStart, endMs: 0, text: lead));
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final start = _tagToMs(match.group(1)!, match.group(2)!, match.group(3)) ?? lineStart;
    final text = body.substring(
      match.end,
      i + 1 < matches.length ? matches[i + 1].start : body.length,
    );
    if (text.trim().isEmpty) continue;
    final next = i + 1 < matches.length
        ? _tagToMs(matches[i + 1].group(1)!, matches[i + 1].group(2)!, matches[i + 1].group(3))
        : null;
    words.add((startMs: start, endMs: next != null && next > start ? next : 0, text: text));
  }
  return words;
}

String _stripInline(String body) => body.replaceAll(_inlineTag, '').trim();

String _stripMarkers(String body, RegExp marker) => body.replaceAll(marker, '').trim();

int _readOffset(String raw) {
  final match = _offsetTag.firstMatch(raw);
  if (match == null) return 0;
  return int.tryParse(match.group(1)!) ?? 0;
}

int? _tagToMs(String minute, String second, String? fraction) {
  final m = int.tryParse(minute);
  final s = int.tryParse(second);
  if (m == null || s == null) return null;
  var extra = 0;
  if (fraction != null) {
    final f = int.tryParse(fraction);
    if (f == null) return null;
    // 1 位是 1/10 秒，2 位是 1/100 秒，3 位是毫秒。
    extra = switch (fraction.length) {
      1 => f * 100,
      2 => f * 10,
      _ => f,
    };
  }
  return ((m * 60) + s) * 1000 + extra;
}

/// 当前播放位置对应的歌词下标；还没有进入第一句时返回 -1。
int lyricIndexAt(List<LyricLine> lines, int positionMs) {
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startMs > positionMs) break;
    index = i;
  }
  return index;
}

/// 转回标准 LRC 文本：C 端/对外协议只需要行级歌词。
String toLrcText(Iterable<LyricLine> lines) => [
      for (final line in lines)
        if (line.text.trim().isNotEmpty) '[${_stamp(line.startMs)}]${line.text}',
    ].join('\n');

String _stamp(int ms) {
  final value = ms < 0 ? 0 : ms;
  final minute = value ~/ 60000;
  final second = (value ~/ 1000) % 60;
  final fraction = value % 1000;
  return '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}.'
      '${fraction.toString().padLeft(3, '0')}';
}
