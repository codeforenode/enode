import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';
import '../l10n/l10n.dart';

/// 源码里不内置任何 broker 凭据：连接参数由「设置 → 广播」整段粘贴后存在本机，
/// 留空即未配置，不发起连接。
const String kMqttTopicPrefix = defaultTopicPrefix;

class MqttConfig {
  const MqttConfig({
    this.host = '',
    this.port = 1883,
    this.tls = false,
    this.username = '',
    this.password = '',
    this.topicPrefix = kMqttTopicPrefix,
    this.clientId = '',
    this.enabled = true,
  });

  final String host;
  final int port;
  final bool tls;
  final String username;
  final String password;
  final String topicPrefix;
  final String clientId;
  final bool enabled;

  /// 没填地址就是还没配过：此时不连接，状态显示「未配置」。
  bool get configured => host.trim().isNotEmpty;

  bool get isValid => validationError == null;

  String? get validationError {
    if (host.trim().isEmpty) return l10n.configHostRequired;
    if (port < 1 || port > 65535) return l10n.configPortRange;
    if (!validTopicPrefix(topicPrefix)) return l10n.configTopicPrefix;
    if (clientId.length > 64) return l10n.configClientIdTooLong;
    return null;
  }

  Map<String, Object?> toJson() => {
        'host': host,
        'port': port,
        'tls': tls,
        'username': username,
        'password': password,
        'topicPrefix': topicPrefix,
        'clientId': clientId,
        'enabled': enabled,
      };

  static MqttConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final host = raw['host'];
    final port = raw['port'];
    if (host is! String || host.trim().isEmpty || port is! num) return null;
    final prefix = raw['topicPrefix'];
    return MqttConfig(
      host: host,
      port: port.toInt(),
      tls: raw['tls'] == true,
      username: raw['username'] is String ? raw['username'] as String : '',
      password: raw['password'] is String ? raw['password'] as String : '',
      topicPrefix: prefix is String && prefix.isNotEmpty ? prefix : kMqttTopicPrefix,
      clientId: raw['clientId'] is String ? raw['clientId'] as String : '',
      enabled: raw['enabled'] != false,
    );
  }
}

/// 「广播」页保存的参数；没存过就是未配置。
class MqttConfigStore {
  static const _key = 'mqtt.config.v1';

  static Future<MqttConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_key);
    if (text == null) return null;
    try {
      final config = MqttConfig.fromJson(jsonDecode(text));
      if (config == null || !config.isValid) return null;
      return config;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(MqttConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
