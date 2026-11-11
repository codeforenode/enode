import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../l10n/l10n.dart';
import '../log.dart';
import 'config.dart';
import 'library.dart';
import 'node_id.dart';
import 'protocol.dart';

enum EdgeStatus { disabled, connecting, connected, error }

typedef SearchFn = Future<({List<Track> items, int total})> Function(String q, int offset, int limit);
typedef EnqueueFn = FutureOr<EnqueueResult> Function(EnqueueRequest req);
typedef SnapshotFn = Map<String, Object?> Function();
typedef HealthFn = Map<String, Object?> Function();

/// 出厂歌单的应答体（纯内存，不需要异步）：`{ready, resolved, failed, seed, items}`。
typedef FeaturedFn = Map<String, Object?> Function();

/// 当前曲目的歌词体：`{trackKey, format, offsetMs, text}`；无曲目时返回 null。
/// 歌词可能来自文件/远程音源，因此和 any-listen 的资源接口一样是异步的。
typedef LyricFn = Future<Map<String, Object?>?> Function();

/// B端 的对外边缘节点：MQTT 参数来自本机保存的 [MqttConfig]（源码不内置），
/// 未配置时不连接；健康公布、队列快照/事件、歌词、检索与入队 RPC 全部经 MQTT。
///
/// 曲库内容永远不出本机：`health` 只上报计数与负载，检索在本地完成。
class EdgeNode extends ChangeNotifier {
  EdgeNode({
    required this.search,
    required this.enqueue,
    required this.snapshot,
    required this.health,
    required this.lyric,
    required this.featured,
    MqttConfig? config,
  }) : config = config ?? const MqttConfig() {
    unawaited(_init());
  }

  static const _healthPeriod = Duration(seconds: 10);
  static const _tickPeriod = Duration(seconds: 5);
  static const _requestCacheTtlMs = 10 * 60 * 1000;
  static const _staleRequestMs = 30 * 1000;
  static const _enqueuePerMinute = 6;
  static const _searchTimeout = Duration(seconds: 8);

  final SearchFn search;
  final EnqueueFn enqueue;
  final SnapshotFn snapshot;
  final HealthFn health;
  final LyricFn lyric;
  final FeaturedFn featured;

  /// 「广播」页改了参数就整体换掉并重连。
  MqttConfig config;

  /// 自动生成、跨重装稳定的节点标识；连接建立前可能为空。
  String? _nodeId;
  String get nodeId => _nodeId ?? '';
  EdgeStatus status = EdgeStatus.disabled;
  String? lastError;
  DateTime? connectedAt;

  int _seq = 0;
  int searchServed = 0;
  int enqueueServed = 0;
  int _searchTotalMs = 0;

  int get searchAvgMs => searchServed == 0 ? 0 : (_searchTotalMs / searchServed).round();

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;
  Timer? _healthTimer;
  Timer? _tickTimer;
  Timer? _retryTimer;
  int _retryDelaySec = 3;
  bool _closing = false;
  bool _disposed = false;

  final Map<String, _CachedResponse> _responses = {};
  final Map<String, List<int>> _guestHits = {};
  final Map<String, Future<Map<String, Object?>>> _enqueueInflight = {};

  bool get connected => status == EdgeStatus.connected;

  String get statusLabel {
    if (!config.configured) return l10n.mqttNotConfigured;
    if (!config.isValid) return l10n.mqttInvalidConfig;
    return switch (status) {
      EdgeStatus.connected => l10n.mqttConnected,
      EdgeStatus.connecting => l10n.mqttConnecting,
      EdgeStatus.error => l10n.mqttFailed,
      EdgeStatus.disabled => l10n.mqttDisconnected,
    };
  }

  String get healthTopicName => healthTopic(config.topicPrefix, nodeId);
  String get queueTopicName => queueTopic(config.topicPrefix, nodeId);
  String get lyricTopicName => lyricTopic(config.topicPrefix, nodeId);
  String get eventsTopicName => eventsTopic(config.topicPrefix, nodeId);
  String get searchReqTopicName => searchReqTopic(config.topicPrefix, nodeId);
  String get enqueueReqTopicName => enqueueReqTopic(config.topicPrefix, nodeId);
  String get featuredReqTopicName => featuredReqTopic(config.topicPrefix, nodeId);

  Future<void> _init() async {
    _nodeId = await NodeIdentity.ensure();
    notifyListeners();
    if (_disposed || !config.enabled || !config.configured) return;
    unawaited(connect());
  }

  /// 运行时替换连接参数：先断开旧连接，再按新参数重连。
  Future<void> applyConfig(MqttConfig next) async {
    if (_disposed) return;
    config = next;
    _retryDelaySec = 3;
    if (!config.enabled || !config.configured) {
      await publishOffline();
      await _closeClient();
      status = EdgeStatus.disabled;
      lastError = null;
      notifyListeners();
      return;
    }
    await connect();
  }

  Future<void> connect() async {
    _nodeId ??= await NodeIdentity.ensure();
    await _closeClient();
    if (!config.configured) {
      status = EdgeStatus.disabled;
      lastError = null;
      notifyListeners();
      return;
    }
    if (!config.isValid) {
      status = EdgeStatus.error;
      lastError = config.validationError;
      notifyListeners();
      return;
    }
    status = EdgeStatus.connecting;
    lastError = null;
    notifyListeners();

    final cid = _resolveClientId();
    final c = MqttServerClient.withPort(config.host.trim(), cid, config.port);
    c.logging(on: false);
    c.setProtocolV311();
    c.keepAlivePeriod = 30;
    c.connectTimeoutPeriod = 8000;
    c.autoReconnect = false;
    c.secure = config.tls;
    final will = jsonEncode({
      'v': protocolVersion,
      'state': stateOffline,
      'node': nodeId,
      'ts': _now(),
    });
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(cid)
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain()
        .withWillTopic(healthTopicName)
        .withWillMessage(will)
        .authenticateAs(
          config.username.trim().isEmpty ? null : config.username.trim(),
          config.password.isEmpty ? null : config.password,
        )
        .startClean();
    c.onConnected = _handleConnected;
    c.onDisconnected = _handleDisconnected;
    _client = c;

    try {
      await c.connect(
        config.username.trim().isEmpty ? null : config.username.trim(),
        config.password.isEmpty ? null : config.password,
      );
    } catch (e) {
      lastError = l10n.connectFailed('$e');
      EnodeLog.e('mqtt', '连接失败 host=${config.host} port=${config.port}', e);
      status = EdgeStatus.error;
      notifyListeners();
      _scheduleRetry();
      return;
    }

    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      lastError = l10n.connectNotEstablished('${c.connectionStatus?.state}');
      EnodeLog.e('mqtt', '连接未建立 state=${c.connectionStatus?.state} err=$lastError');
      status = EdgeStatus.error;
      notifyListeners();
      _scheduleRetry();
    }
  }

  void _handleConnected() {
    status = EdgeStatus.connected;
    lastError = null;
    connectedAt = DateTime.now();
    _retryDelaySec = 3;
    _retryTimer?.cancel();
    EnodeLog.i('mqtt', '已连接 node=$nodeId host=${config.host}:${config.port}');

    final c = _client;
    // updates 只有在连接建立后才可用，必须在此刻挂接，否则收不到任何下行消息。
    _sub ??= c?.updates?.listen(_handleMessages);
    c?.subscribe(searchReqTopicName, MqttQos.atLeastOnce);
    c?.subscribe(enqueueReqTopicName, MqttQos.atLeastOnce);
    c?.subscribe(featuredReqTopicName, MqttQos.atLeastOnce);

    publishHealth();
    publishSnapshot();
    publishLyric();
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_healthPeriod, (_) => publishHealth());
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickPeriod, (_) => _publishTick());
    notifyListeners();
  }

  void _handleDisconnected() {
    _healthTimer?.cancel();
    _tickTimer?.cancel();
    if (_closing || _disposed) return;
    status = EdgeStatus.error;
    lastError = l10n.connectionClosed;
    EnodeLog.w('mqtt', '连接断开 node=$nodeId');
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || !config.enabled || !config.configured) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: _retryDelaySec), () {
      if (!_disposed && config.enabled && config.configured) unawaited(connect());
    });
    _retryDelaySec = min(_retryDelaySec * 2, 30);
  }

  Future<void> _closeClient() async {
    _closing = true;
    _healthTimer?.cancel();
    _tickTimer?.cancel();
    _retryTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        c.onConnected = null;
        c.onDisconnected = null;
        c.disconnect();
      } catch (_) {}
    }
    _closing = false;
    if (connected) status = EdgeStatus.disabled;
  }

  String _resolveClientId() {
    final custom = config.clientId.trim();
    if (custom.isNotEmpty) return custom;
    final suffix = nodeId.startsWith('nd-') ? nodeId.substring(3) : nodeId;
    return 'bp-$suffix';
  }

  // ---------------- 发布 ----------------

  Map<String, Object?> buildSnapshotMessage() {
    final body = snapshot();
    return {
      'v': protocolVersion,
      'seq': ++_seq,
      'node': nodeId,
      'ts': _now(),
      ...body,
    };
  }

  /// 正常退出/关闭 MQTT 前主动补发 retained 离线状态。
  ///
  /// 遗嘱只在异常断链时由 broker 发布；正常 DISCONNECT 不会发，
  /// 中继只能等 health 过期（35s）才判定离线，C端会一直显示“已连接”。
  Future<void> publishOffline({Duration settle = const Duration(milliseconds: 250)}) async {
    if (!connected) return;
    final message = jsonEncode({
      'v': protocolVersion,
      'state': stateOffline,
      'node': nodeId,
      'ts': _now(),
    });
    _publish(healthTopicName, message, retain: true);
    // QoS1 发布是异步的，给 broker 留出收发时间，再把连接断掉。
    await Future<void>.delayed(settle);
  }

  void publishHealth() {
    if (!connected) return;
    final extra = health();
    final uptime = connectedAt == null ? 0 : _now() - connectedAt!.millisecondsSinceEpoch;
    final message = {
      'v': protocolVersion,
      'state': stateOnline,
      'ts': _now(),
      'node': nodeId,
      'uptimeMs': uptime,
      'queueDepth': extra['queueDepth'] ?? 0,
      'playing': extra['playing'] ?? false,
      'library': extra['library'] ?? const {},
      'load': {
        'searchServed': searchServed,
        'searchAvgMs': searchAvgMs,
        'enqueueServed': enqueueServed,
      },
      'caps': extra['caps'] is List ? List<String>.from(extra['caps'] as List) : capsV1,
      'app': const {'name': 'b-player', 'version': '0.1.0'},
    };
    _publish(healthTopicName, jsonEncode(message), retain: true);
  }

  void publishSnapshot() {
    if (!connected) return;
    _publish(queueTopicName, jsonEncode(buildSnapshotMessage()), retain: true);
  }

  void notifyQueueChanged() {
    if (!connected) return;
    final message = buildSnapshotMessage();
    _publish(queueTopicName, jsonEncode(message), retain: true);
    _publishEvent(eQueueUpdate, {'queue': message['queue'] ?? const []});
  }

  void notifyPlayback() {
    if (!connected) return;
    final message = buildSnapshotMessage();
    _publish(queueTopicName, jsonEncode(message), retain: true);
    final player = message['player'];
    final rate = player is Map ? player['rate'] : 0;
    _publishEvent(ePlayerState, {'rate': rate});
  }

  void notifyTrackChanged() {
    if (!connected) return;
    final message = buildSnapshotMessage();
    _publish(queueTopicName, jsonEncode(message), retain: true);
    final player = message['player'];
    _publishEvent(ePlayerTrack, player is Map ? Map<String, Object?>.from(player) : const {});
    _publishEvent(eQueueUpdate, {'queue': message['queue'] ?? const []});
    publishLyric();
  }

  /// 歌词与曲目信息只走 MQTT：当前曲目歌词整段保留在 `lyric` 主题上。
  int _lyricGeneration = 0;

  void publishLyric() {
    if (!connected) return;
    final generation = ++_lyricGeneration;
    unawaited(_publishLyricAsync(generation));
  }

  Future<void> _publishLyricAsync(int generation) async {
    Map<String, Object?>? body;
    try {
      body = await lyric();
    } catch (_) {
      body = null;
    }
    // 歌词读取期间曲目可能已经切走，旧结果不能覆盖新曲目的 retained 消息。
    if (generation != _lyricGeneration || !connected) return;
    final message = <String, Object?>{
      'v': protocolVersion,
      'node': nodeId,
      'ts': _now(),
      if (body == null) ...{
        'trackKey': null,
        'format': 'lrc',
        'offsetMs': 0,
        'rev': '',
        'text': '',
      } else ...body,
    };
    final text = message['text'];
    if (text is String && text.isNotEmpty) {
      message['rev'] = sha256.convert(utf8.encode(text)).toString().substring(0, 8);
    }
    EnodeLog.d(
      'lyric',
      '发布 ${text is String ? text.length : 0} 字符 rev=${message['rev'] ?? '-'}',
    );
    _publish(lyricTopicName, jsonEncode(message), retain: true);
  }

  void _publishTick() {
    if (!connected) return;
    final body = snapshot();
    final player = body['player'];
    if (player is! Map) return;
    _publishEvent(ePlayerTick, {
      'positionMs': player['positionMs'],
      'sampledAtMs': player['sampledAtMs'],
      'rate': player['rate'],
    });
  }

  void _publishEvent(String type, Map<String, Object?> data) {
    if (!connected) return;
    final message = {
      'v': protocolVersion,
      'seq': ++_seq,
      'type': type,
      'at': _now(),
      'data': data,
    };
    _publish(eventsTopicName, jsonEncode(message));
  }

  void _publish(String topic, String payload, {bool retain = false}) {
    final c = _client;
    if (c == null || c.connectionStatus?.state != MqttConnectionState.connected) {
      // 发不出去时中继只会干等到超时，看起来像节点挂了。留一条痕迹，
      // 而且要能在日志里和「已连接」对上时间。
      EnodeLog.d('mqtt', '未连接，丢弃发布 topic=$topic ${payload.length} 字节');
      return;
    }
    try {
      // addString 不是 UTF-8：中文会被拆成 UTF-16 半字，必须用 addUTF8String。
      final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
      c.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
    } catch (e) {
      lastError = l10n.publishFailed('$e');
      // 不记 payload：入队应答里有桌号，歌词里有正文。
      EnodeLog.w('mqtt', '发布失败 topic=$topic ${payload.length} 字节', e);
      notifyListeners();
    }
  }

  // ---------------- 订阅处理 ----------------

  void _handleMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final m in messages) {
      final payload = m.payload;
      if (payload is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      switch (m.topic) {
        case final t when t == searchReqTopicName:
          unawaited(_handleSearch(text));
        case final t when t == enqueueReqTopicName:
          _handleEnqueue(text);
        case final t when t == featuredReqTopicName:
          _handleFeatured(text);
      }
    }
  }

  /// 检索会走在线音源，必须异步并整体限时。
  Future<void> _handleSearch(String text) async {
    final env = EdgeEnvelope.parse(_decodeJson(text));
    if (env == null || env.type != tSearchReq || env.node != nodeId) return;
    final nonce = env.nonce?.trim();
    if (nonce == null || nonce.isEmpty) return;
    final topic = searchRespTopic(config.topicPrefix, nodeId, nonce);
    final sw = Stopwatch()..start();
    try {
      final req = SearchRequest.fromPayload(env.payload);
      final result = await search(req.q, req.offset, req.limit).timeout(_searchTimeout);
      sw.stop();
      searchServed++;
      _searchTotalMs += sw.elapsedMilliseconds;
      _respond(topic, EdgeEnvelope(
        type: tSearchResp,
        node: nodeId,
        ts: _now(),
        nonce: nonce,
        payload: {
          'ok': true,
          'total': result.total,
          'offset': req.offset,
          'limit': req.limit,
          'tookMs': sw.elapsedMilliseconds,
          'items': [
            for (final t in result.items)
              {
                'trackKey': t.trackKey,
                'title': t.title,
                'artist': t.artist,
                'durationMs': t.durationMs,
                'source': t.sourceId,
              },
          ],
        },
      ));
    } on FormatException catch (e) {
      _respond(topic, _errorEnvelope(tSearchResp, nonce, errBadRequest, e.message));
    } on TimeoutException {
      _respond(topic, _errorEnvelope(tSearchResp, nonce, errInternal, l10n.searchTimeout));
    } catch (_) {
      _respond(topic, _errorEnvelope(tSearchResp, nonce, errInternal, null));
    }
    notifyListeners();
  }

  /// 出厂歌单只读内存，不触碰音源，也没有超时风险。
  void _handleFeatured(String text) {
    final env = EdgeEnvelope.parse(_decodeJson(text));
    if (env == null || env.type != tFeaturedReq || env.node != nodeId) return;
    final nonce = env.nonce?.trim();
    if (nonce == null || nonce.isEmpty) return;
    final topic = featuredRespTopic(config.topicPrefix, nodeId, nonce);
    try {
      final body = featured();
      _respond(topic, EdgeEnvelope(
        type: tFeaturedResp,
        node: nodeId,
        ts: _now(),
        nonce: nonce,
        payload: {'ok': true, ...body},
      ));
    } catch (_) {
      _respond(topic, _errorEnvelope(tFeaturedResp, nonce, errInternal, null));
    }
  }

  void _handleEnqueue(String text) {
    final env = EdgeEnvelope.parse(_decodeJson(text));
    if (env == null || env.type != tEnqueueReq) {
      // 解析不出来通常是接入方把 payload 写坏了；别静默丢弃，否则中继那边只能等到超时。
      EnodeLog.w('mqtt', '收到无法解析的入队报文 ${text.length} 字节');
      return;
    }
    if (env.node != nodeId) {
      // 报文指定的不是本机。共享 broker 且没配 TARGET_NODE 时会走到这里，
      // 是中继挑错节点的直接证据。
      EnodeLog.d('mqtt', '入队报文发给了 ${env.node}，本机是 $nodeId，忽略');
      return;
    }
    final nonce = env.nonce?.trim();
    if (nonce == null || nonce.isEmpty) {
      EnodeLog.w('mqtt', '入队报文缺少 nonce，无法应答');
      return;
    }
    final topic = enqueueRespTopic(config.topicPrefix, nodeId, nonce);
    final now = _now();

    final EnqueueRequest req;
    try {
      req = EnqueueRequest.fromPayload(env.payload, envelopeTs: env.ts);
    } on FormatException catch (e) {
      EnodeLog.w('queue', '拒绝入队请求：报文不合法 ${e.message}');
      _respond(topic, _errorEnvelope(tEnqueueResp, nonce, errBadRequest, e.message));
      return;
    }

    if (req.ts != 0 && now - req.ts > _staleRequestMs) {
      EnodeLog.w('queue', '拒绝入队请求：已过期 ${(now - req.ts) ~/ 1000}s requestId=${req.requestId}');
      _respond(topic, _errorEnvelope(tEnqueueResp, nonce, errStale, null));
      return;
    }

    final cached = _responses[req.requestId];
    if (cached != null && now - cached.atMs < _requestCacheTtlMs) {
      // 幂等重试：上一次已经在处理或已处理完，直接回同一份结果。
      EnodeLog.d('queue', '重复 requestId=${req.requestId}，返回 ${(now - cached.atMs) ~/ 1000}s 前的结果');
      _respond(topic, EdgeEnvelope(
        type: tEnqueueResp,
        node: nodeId,
        ts: now,
        nonce: nonce,
        payload: cached.payload,
      ));
      return;
    }

    if (req.tag != null && !_allowEnqueue(req.tag!, now)) {
      // 顾客「点了没反应」最常见的原因之一：C端 只看到「请求太频繁」，
      // 现场没人知道是哪个客户端刷过头了。
      EnodeLog.w(
        'queue',
        '限流 tag=${EnodeLog.shortId(req.tag!)}${req.seat == null ? '' : ' seat=${req.seat}'}'
        '（1 分钟内超过 $_enqueuePerMinute 次）',
      );
      _respond(topic, _errorEnvelope(tEnqueueResp, nonce, errRateLimited, null));
      return;
    }

    // 入队要先取链，应答因此是异步的；同一 requestId 的并发重试共用这一次解析。
    final work = _enqueueInflight[req.requestId] ??= _serveEnqueue(req);
    unawaited(work.then((payload) {
      _respond(topic, EdgeEnvelope(
        type: tEnqueueResp,
        node: nodeId,
        ts: _now(),
        nonce: nonce,
        payload: payload,
      ));
      notifyListeners();
    }, onError: (Object _) {
      // 回调里抛异常也必须应答，否则中继只能等到超时。
      _respond(topic, _errorEnvelope(tEnqueueResp, nonce, errInternal, null));
      notifyListeners();
    }));
  }

  Future<Map<String, Object?>> _serveEnqueue(EnqueueRequest req) async {
    try {
      final result = await enqueue(req);
      enqueueServed++;
      final payload = <String, Object?>{
        'ok': result.accepted,
        'result': result.accepted ? 'accepted' : 'rejected',
        if (result.queuePosition != null) 'queuePosition': result.queuePosition,
        if (result.reason != null) 'reason': result.reason,
        if (result.message != null) 'message': result.message,
        'trackKey': req.trackKey,
        'requestId': req.requestId,
      };
      final now = _now();
      _responses[req.requestId] = _CachedResponse(now, payload);
      _pruneResponses(now);
      return payload;
    } finally {
      _enqueueInflight.remove(req.requestId);
    }
  }

  bool _allowEnqueue(String tag, int now) {
    final hits = _guestHits.putIfAbsent(tag, () => []);
    hits.removeWhere((t) => now - t > 60000);
    if (hits.length >= _enqueuePerMinute) return false;
    hits.add(now);
    return true;
  }

  void _pruneResponses(int now) {
    if (_responses.length < 512) return;
    _responses.removeWhere((_, v) => now - v.atMs > _requestCacheTtlMs);
  }

  EdgeEnvelope _errorEnvelope(String type, String nonce, String code, String? message) => EdgeEnvelope(
        type: type,
        node: nodeId,
        ts: _now(),
        nonce: nonce,
        payload: {
          'ok': false,
          'error': code,
          'message': ?message,
        },
      );

  void _respond(String topic, EdgeEnvelope envelope) {
    _publish(topic, jsonEncode(envelope.toJson()));
  }

  Object? _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _disposed = true;
    _healthTimer?.cancel();
    _tickTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_sub?.cancel());
    try {
      _client?.disconnect();
    } catch (_) {}
    super.dispose();
  }
}

class _CachedResponse {
  _CachedResponse(this.atMs, this.payload);
  final int atMs;
  final Map<String, Object?> payload;
}
