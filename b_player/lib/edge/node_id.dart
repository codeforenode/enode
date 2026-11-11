import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../log.dart';

/// 节点 ID：B端 首次启动时自己生成一个随机标识，写入本机后长期沿用。
///
/// 为什么不拿设备硬件标识派生：批量部署常从同一份系统镜像克隆，
/// `MachineGuid` / Android ID 会完全一样，几十台节点算出来的 ID 全撞在一起——
/// 主题互相覆盖，入队还会落到别的机器上。随机值与硬件无关，克隆多少台都不会重样。
///
/// 兼容老版本：已有落盘值一律沿用（格式没变，仍是 `nd-` + 16 位十六进制），
/// 升级后节点 ID 保持不变，中继的 `TARGET_NODE` 与 retained 主题都还认得。
///
/// 代价：卸载并清空应用数据后会生成新的 ID，需要在接入方重新绑定。
abstract final class NodeIdentity {
  static const _prefsKey = 'edge.node.id';
  static final _format = RegExp(r'^nd-[0-9a-f]{16}$');

  static String? _cached;
  static Future<String>? _pending;

  static String? get cached => _cached;

  /// 仅测试用：清掉进程内缓存，模拟一次冷启动。
  @visibleForTesting
  static void resetCacheForTest() {
    _cached = null;
    _pending = null;
  }

  static Future<String> ensure() {
    final hit = _cached;
    if (hit != null) return Future.value(hit);
    return _pending ??= _resolve().whenComplete(() => _pending = null);
  }

  static Future<String> _resolve() async {
    // 老版本存过的 ID 一律沿用：升级不能换身份。
    final saved = await _read();
    if (saved != null) return _cached = saved;
    final id = _randomId();
    _cached = id;
    await _write(id);
    return id;
  }

  /// 8 字节随机（64 位）：几百台规模的碰撞概率可以忽略，且与硬件信息无关。
  static String _randomId() {
    final r = Random.secure();
    final hex = List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'nd-$hex';
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
    } catch (e) {
      // 完全静默的话：ID 只活在内存里，重启就换新号——中继的 TARGET_NODE 失联、
      // 旧 retained 主题全部作废，现场日志里却一条线索都没有。
      EnodeLog.w('app', 'nodeId 落盘失败，本次运行的 ID 重启后不保留：$e');
    }
  }
}
