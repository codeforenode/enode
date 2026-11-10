import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/edge/protocol.dart';

/// 入队请求的曲目提示用于「本机没检索过这首」时的兜底映射（协议 §10.3）。
/// 它是可选字段：旧客户端不带、旧节点不认，都必须保持原行为。
void main() {
  EnqueueRequest parse(Map<String, Object?> payload) =>
      EnqueueRequest.fromPayload(payload, envelopeTs: 1000);

  Map<String, Object?> body({Map<String, Object?>? hint}) => {
        'trackKey': 'lx:abc123',
        'requestId': 'r-1',
        'guest': {'seat': 'A3', 'tag': 'g-1a2b3c4d'},
        'hint': ?hint,
      };

  test('不带 hint 时与旧协议完全一致', () {
    final req = parse(body());
    expect(req.hint, isNull);
    expect(req.seat, 'A3');
    expect(req.tag, 'g-1a2b3c4d');
    expect(req.trackKey, 'lx:abc123');
  });

  test('解析 hint 的歌名、歌手与时长，并去掉首尾空白', () {
    final req = parse(body(hint: {
      'title': ' 如愿 ',
      'artist': ' 王菲 ',
      'durationMs': 265000,
    }));
    expect(req.hint?.title, '如愿');
    expect(req.hint?.artist, '王菲');
    expect(req.hint?.durationMs, 265000);
  });

  test('hint 缺歌名或类型不对时视为没有，不影响入队本身', () {
    expect(parse(body(hint: {'artist': '王菲'})).hint, isNull);
    expect(parse(body(hint: {'title': '   '})).hint, isNull);
    expect(parse(body(hint: {'title': 123})).hint, isNull);
    expect(parse({...body(), 'hint': '如愿'}).hint, isNull);
    // trackKey 仍然可用，入队不会被兜底字段拖垮
    expect(parse(body(hint: {'title': 123})).trackKey, 'lx:abc123');
  });

  test('时长不合法时归零，歌名仍然保留', () {
    final req = parse(body(hint: {'title': '如愿', 'durationMs': 'abc'}));
    expect(req.hint?.title, '如愿');
    expect(req.hint?.durationMs, 0);
  });

  test('检索参数传字符串时退回默认值，不抛类型错误', () {
    final req = SearchRequest.fromPayload({
      'q': '晴天',
      'offset': '10',
      'limit': 'abc',
    });
    expect(req.offset, 0);
    expect(req.limit, 20);
  });
}
