/// B端 边缘节点对外协议（MQTT v1）的编解码与主题命名。
///
/// 对接文档见 `docs/edge-integration-protocol.md`；
/// 本文件只做结构校验，不包含任何业务决策。
library;

const int protocolVersion = 1;
const String defaultTopicPrefix = 'node';

// ---------- 消息类型 ----------
const String tSearchReq = 'search.req';
const String tSearchResp = 'search.resp';
const String tEnqueueReq = 'enqueue.req';
const String tEnqueueResp = 'enqueue.resp';

const String eQueueUpdate = 'queue.update';
const String ePlayerTrack = 'player.track';
const String ePlayerState = 'player.state';
const String ePlayerTick = 'player.tick';

// ---------- 健康状态 ----------
const String stateOnline = 'online';
const String stateDegraded = 'degraded';
const String stateOffline = 'offline';

// ---------- 稳定错误码 ----------
const String errBadRequest = 'BAD_REQUEST';
const String errRateLimited = 'RATE_LIMITED';
const String errQueueFull = 'QUEUE_FULL';
const String errTrackNotFound = 'TRACK_NOT_FOUND';
const String errSourceUnavailable = 'SOURCE_UNAVAILABLE';
const String errStale = 'STALE_REQUEST';
const String errInternal = 'INTERNAL';

const List<String> capsV1 = ['search', 'enqueue', 'snapshot', 'events'];

final RegExp _nodeRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// 节点 ID 由 B端 自动生成，外部只做格式校验，不参与分配。
bool validNodeId(String v) => _nodeRe.hasMatch(v);

bool validTopicPrefix(String p) => p.trim().isNotEmpty && !RegExp(r'[#+\s]').hasMatch(p);

String healthTopic(String prefix, String node) => '$prefix/$node/health';
String queueTopic(String prefix, String node) => '$prefix/$node/queue';
String lyricTopic(String prefix, String node) => '$prefix/$node/lyric';
String eventsTopic(String prefix, String node) => '$prefix/$node/events';
String searchReqTopic(String prefix, String node) => '$prefix/$node/rpc/search.req';
String enqueueReqTopic(String prefix, String node) => '$prefix/$node/rpc/enqueue.req';
String searchRespTopic(String prefix, String node, String nonce) => '$prefix/$node/rpc/search.resp/$nonce';
String enqueueRespTopic(String prefix, String node, String nonce) => '$prefix/$node/rpc/enqueue.resp/$nonce';

class EdgeEnvelope {
  const EdgeEnvelope({
    required this.type,
    required this.node,
    required this.ts,
    this.nonce,
    this.payload = const {},
  });

  final String type;
  final String node;
  final int ts;
  final String? nonce;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
        'v': protocolVersion,
        'type': type,
        'node': node,
        'ts': ts,
        if (nonce != null) 'nonce': nonce,
        'payload': payload,
      };

  static EdgeEnvelope? parse(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final node = raw['node'];
    if (type is! String || node is! String) return null;
    final payload = raw['payload'];
    return EdgeEnvelope(
      type: type,
      node: node,
      ts: (raw['ts'] as num?)?.toInt() ?? 0,
      nonce: raw['nonce'] is String ? raw['nonce'] as String : null,
      payload: payload is Map ? Map<String, Object?>.from(payload) : const {},
    );
  }
}

/// 检索请求参数。非法输入抛 [FormatException]，由调用方回 BAD_REQUEST。
class SearchRequest {
  const SearchRequest({required this.q, this.offset = 0, this.limit = 20});

  final String q;
  final int offset;
  final int limit;

  static SearchRequest fromPayload(Map<String, Object?> p) {
    final q = p['q'];
    if (q is! String || q.trim().isEmpty || q.runes.length > 64) {
      throw const FormatException('q 必须为 1–64 字符');
    }
    final offset = (p['offset'] as num?)?.toInt() ?? 0;
    final limit = (p['limit'] as num?)?.toInt() ?? 20;
    if (offset < 0 || offset > 1000) throw const FormatException('offset 越界');
    if (limit < 1 || limit > 50) throw const FormatException('limit 越界');
    return SearchRequest(q: q, offset: offset, limit: limit);
  }
}

class SearchHit {
  const SearchHit({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.durationMs,
  });

  final String trackKey;
  final String title;
  final String artist;
  final int durationMs;

  Map<String, Object?> toJson() => {
        'trackKey': trackKey,
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
      };
}

class EnqueueRequest {
  const EnqueueRequest({
    required this.trackKey,
    required this.requestId,
    this.seat,
    this.tag,
    this.ts = 0,
  });

  final String trackKey;
  final String requestId;
  final String? seat;
  final String? tag;
  final int ts;

  static EnqueueRequest fromPayload(Map<String, Object?> p, {int envelopeTs = 0}) {
    final trackKey = p['trackKey'];
    final requestId = p['requestId'];
    if (trackKey is! String || trackKey.isEmpty || trackKey.length > 128) {
      throw const FormatException('trackKey 非法');
    }
    if (requestId is! String || requestId.isEmpty || requestId.length > 96) {
      throw const FormatException('requestId 非法');
    }
    String? optString(Object? v) {
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final guest = p['guest'];
    final guestMap = guest is Map ? guest : const {};
    return EnqueueRequest(
      trackKey: trackKey,
      requestId: requestId,
      seat: optString(guestMap['seat']),
      tag: optString(guestMap['tag']),
      ts: envelopeTs,
    );
  }
}

class EnqueueResult {
  const EnqueueResult.accepted(int this.queuePosition)
      : accepted = true,
        reason = null,
        message = null;

  const EnqueueResult.rejected(this.reason, [this.message])
      : accepted = false,
        queuePosition = null;

  final bool accepted;
  final String? reason;

  /// 可以直接给顾客看的一句话；只在拒绝时有意义。
  final String? message;
  final int? queuePosition;
}
