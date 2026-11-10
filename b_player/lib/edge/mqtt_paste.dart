import 'dart:convert';

import 'config.dart';
import '../l10n/l10n.dart';

/// 把用户粘进来的一段连接信息解析成 MQTT 参数。
///
/// 支持这几种常见写法（含中文标签、全角冒号）：
/// - `mqtt://账号:密码@地址:端口`、`mqtts://…`
/// - `账号:密码@地址:端口`、`地址:端口`
/// - 多行键值：`Broker: 地址` / `端口: 1883` / `用户名: …` / `密码: …`
/// - 多行裸值：地址、端口、账号、密码各一行
/// - JSON：`{"host":…,"port":…,"username":…,"password":…}`
///
/// 主题前缀与 Client ID 沿用 [base]，不在这段连接信息里。
MqttConfig parseMqttPaste(String raw, {required MqttConfig base}) {
  final text = raw.trim();
  if (text.isEmpty) throw FormatException(l10n.pasteEmpty);
  final normalized = text.replaceAll('：', ':').replaceAll('＠', '@');

  final fromJson = _tryJson(normalized, base);
  if (fromJson != null) return fromJson;
  final fromKeys = _tryKeyValues(normalized, base);
  if (fromKeys != null) return fromKeys;
  final fromUri = _tryUri(normalized, base);
  if (fromUri != null) return fromUri;
  final fromLoose = _tryLoose(normalized, base);
  if (fromLoose != null) return fromLoose;

  throw FormatException(l10n.pasteUnrecognized);
}

const _hostKeys = {'host', 'broker', 'server', 'address', 'addr', '地址', '主机', '服务器'};
const _portKeys = {'port', '端口'};
const _userKeys = {'username', 'user', 'account', '账号', '用户名', '用户'};
const _passKeys = {'password', 'pass', 'pwd', '密码'};
const _tlsKeys = {'tls', 'ssl', 'secure', '加密'};

MqttConfig? _tryJson(String text, MqttConfig base) {
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final fields = <String, Object?>{
    for (final e in decoded.entries)
      if (e.key is String) (e.key as String).trim().toLowerCase(): e.value,
  };
  final host = _pick(fields, _hostKeys);
  if (host == null) throw FormatException(l10n.pasteMissingHost);
  final tls = _truthy(_pick(fields, _tlsKeys));
  final port = _asInt(_pick(fields, _portKeys)) ?? (tls ? 8883 : 1883);
  return _build(
    host,
    port,
    tls,
    _pick(fields, _userKeys) ?? '',
    _pick(fields, _passKeys) ?? '',
    base,
  );
}

MqttConfig? _tryKeyValues(String text, MqttConfig base) {
  final fields = <String, String>{};
  for (final line in text.split(RegExp(r'[\r\n;；]+'))) {
    final m = RegExp(r'^\s*([^:=]{1,16}?)\s*[:=]\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final canon = _canonKey(m.group(1)!);
    final value = m.group(2)!.trim();
    if (canon != null && value.isNotEmpty) fields[canon] = value;
  }
  final rawHost = fields['host'];
  if (rawHost == null) return null;
  final split = _splitHostPort(rawHost);
  final tls = _truthy(fields['tls']);
  final port = _asInt(fields['port']) ?? split.$2;
  return _build(
    split.$1,
    port == 0 ? (tls ? 8883 : 1883) : port,
    tls,
    fields['user'] ?? '',
    fields['pass'] ?? '',
    base,
  );
}

MqttConfig? _tryUri(String text, MqttConfig base) {
  if (text.contains('\n') || text.contains('\r')) return null;
  var candidate = text;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(candidate);
  if (!hasScheme) {
    if (!candidate.contains('@') && !_looksLikeHostPort(candidate)) return null;
    candidate = 'mqtt://$candidate';
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  const supported = {'mqtt', 'mqtts', 'tcp', 'ssl', 'tls'};
  if (!supported.contains(scheme)) {
    if (scheme == 'ws' || scheme == 'wss') {
      throw FormatException(l10n.pasteNoWebsocket);
    }
    return null;
  }
  final tls = scheme == 'mqtts' || scheme == 'ssl' || scheme == 'tls';
  final port = uri.hasPort ? uri.port : (tls ? 8883 : 1883);
  var user = '';
  var pass = '';
  if (uri.userInfo.isNotEmpty) {
    final info = uri.userInfo;
    final i = info.indexOf(':');
    user = _decode(i < 0 ? info : info.substring(0, i));
    pass = i < 0 ? '' : _decode(info.substring(i + 1));
  }
  return _build(uri.host, port, tls, user, pass, base);
}

MqttConfig? _tryLoose(String text, MqttConfig base) {
  final tokens = [
    for (final t in text.split(RegExp(r'[\s,，]+')))
      if (t.trim().isNotEmpty) t.trim(),
  ];
  if (tokens.isEmpty) return null;
  final head = _splitHostPort(tokens.first);
  final host = head.$1;
  if (!_plausibleHost(host)) return null;
  var port = head.$2;
  var start = 1;
  if (port == 0 && tokens.length > 1) {
    final maybe = int.tryParse(tokens[1]);
    if (maybe != null) {
      port = maybe;
      start = 2;
    }
  }
  final rest = tokens.sublist(start);
  return _build(
    host,
    port == 0 ? 1883 : port,
    false,
    rest.isNotEmpty ? rest.first : '',
    rest.length > 1 ? rest.sublist(1).join(' ') : '',
    base,
  );
}

MqttConfig _build(String host, int port, bool tls, String user, String pass, MqttConfig base) {
  final trimmed = host.trim();
  if (trimmed.isEmpty || RegExp(r'\s').hasMatch(trimmed)) {
    throw FormatException(l10n.pasteBadHost);
  }
  final config = MqttConfig(
    host: trimmed,
    port: port,
    tls: tls,
    username: user.trim(),
    password: pass,
    topicPrefix: base.topicPrefix,
    clientId: base.clientId,
    enabled: true,
  );
  final error = config.validationError;
  if (error != null) throw FormatException(error);
  return config;
}

String? _canonKey(String raw) {
  final key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_.\-]'), '');
  if (_hostKeys.contains(key)) return 'host';
  if (_portKeys.contains(key)) return 'port';
  if (_userKeys.contains(key)) return 'user';
  if (_passKeys.contains(key)) return 'pass';
  if (_tlsKeys.contains(key)) return 'tls';
  return null;
}

String? _pick(Map<String, Object?> fields, Set<String> keys) {
  for (final entry in fields.entries) {
    final canon = _canonKey(entry.key);
    if (canon != null && keys.contains(canon) && entry.value != null) {
      final text = '${entry.value}'.trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

int? _asInt(String? raw) => raw == null ? null : int.tryParse(raw.trim());

bool _truthy(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  return const {'true', '1', 'yes', 'on', 'ssl', 'tls', '是', '开', '开启', '启用', '加密'}
      .contains(text);
}

(String, int) _splitHostPort(String value) {
  var text = value.trim();
  if (text.startsWith('[')) {
    final end = text.indexOf(']');
    if (end > 0) {
      final host = text.substring(1, end);
      final rest = text.substring(end + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) ?? 0 : 0;
      return (host, port);
    }
  }
  final i = text.lastIndexOf(':');
  if (i > 0 && text.indexOf(':') == i) {
    final port = int.tryParse(text.substring(i + 1));
    if (port != null) return (text.substring(0, i), port);
  }
  return (text, 0);
}

bool _looksLikeHostPort(String text) =>
    RegExp(r'^[^\s/@:]+:\d{1,5}$').hasMatch(text) ||
    RegExp(r'^[^\s/@:]*\.[^\s/@:]+(:\d{1,5})?$').hasMatch(text) ||
    text.startsWith('localhost');

bool _plausibleHost(String host) =>
    host.contains('.') || host.contains(':') || host == 'localhost';

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
