import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 节点 ID：B端 自动生成，不需要也不允许使用者填写。
///
/// 由设备稳定标识派生并做 SHA-256 截断，因此：
/// - 重装 App、升级版本、清空数据后重新计算，结果不变；
/// - 恢复出厂设置 / 换机后才会变化；
/// - 消息主题里只出现哈希值，不暴露原始硬件标识。
///
/// 取不到设备标识的环境（测试、部分桌面）退化为随机值，只能靠本地持久化保持稳定。
abstract final class NodeIdentity {
  static const _prefsKey = 'edge.node.id';
  static final _format = RegExp(r'^nd-[0-9a-f]{16}$');

  static String? _cached;
  static Future<String>? _pending;

  static String? get cached => _cached;

  static Future<String> ensure() {
    final hit = _cached;
    if (hit != null) return Future.value(hit);
    return _pending ??= _resolve().whenComplete(() => _pending = null);
  }

  static Future<String> _resolve() async {
    final saved = await _read();
    if (saved != null) return _cached = saved;
    final seed = await _deviceSeed();
    final id = seed == null ? _randomId() : _derive(seed);
    _cached = id;
    await _write(id);
    return id;
  }

  static String _derive(String seed) =>
      'nd-${sha256.convert(utf8.encode('enode-edge-node|$seed')).toString().substring(0, 16)}';

  static String _randomId() {
    final r = Random.secure();
    final hex = List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'nd-$hex';
  }

  static Future<String?> _deviceSeed() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) return _nonEmpty((await info.androidInfo).id);
      if (Platform.isIOS) return _nonEmpty((await info.iosInfo).identifierForVendor);
      if (Platform.isWindows) return _nonEmpty((await info.windowsInfo).deviceId);
      if (Platform.isMacOS) return _nonEmpty((await info.macOsInfo).systemGUID);
      if (Platform.isLinux) return _nonEmpty((await info.linuxInfo).machineId);
    } catch (_) {
      // 插件不可用：走随机兜底。
    }
    return null;
  }

  static String? _nonEmpty(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static Future<String?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefsKey);
      return id != null && _format.hasMatch(id) ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, id);
    } catch (_) {}
  }
}
