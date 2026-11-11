import 'dart:io';

import '../log.dart';

/// 开机自启：写当前用户的 Run 键，不需要管理员权限。
/// 值必须带引号，因为安装目录 `C:\Program Files\eNode` 里有空格。
const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _runValue = 'eNode';

/// 读取开机自启状态。
///
/// 调不到 `reg.exe` 时按「未启用」处理：沙箱、企业组策略、杀毒软件都会拦它，
/// 但这些只是让托盘菜单上的勾不准，不该让启动流程抛异常——否则每次启动都会
/// 在日志里留下一条「未捕获的异步异常」，看起来像崩溃。
Future<bool> isAutostartEnabled() async {
  try {
    final result = await Process.run('reg.exe', ['query', _runKey, '/v', _runValue]);
    return result.exitCode == 0;
  } catch (e) {
    EnodeLog.w('autostart', '读取开机自启状态失败，按未启用处理', e);
    return false;
  }
}

/// 写入开机自启；返回是否成功。失败只记日志，不向调用方抛。
Future<bool> setAutostart(bool enable) async {
  try {
    if (enable) {
      final result = await Process.run('reg.exe', [
        'add',
        _runKey,
        '/v',
        _runValue,
        '/t',
        'REG_SZ',
        '/d',
        '"${Platform.resolvedExecutable}"',
        '/f',
      ]);
      if (result.exitCode != 0) {
        EnodeLog.w('autostart', '设置开机自启失败 exit=${result.exitCode}');
        return false;
      }
    } else {
      final result = await Process.run('reg.exe', ['delete', _runKey, '/v', _runValue, '/f']);
      // 删不存在的值会返回非 0，这属于正常的「本来就没开」，不当失败。
      if (result.exitCode != 0 && result.exitCode != 1) {
        EnodeLog.w('autostart', '取消开机自启失败 exit=${result.exitCode}');
        return false;
      }
    }
    EnodeLog.i('autostart', enable ? '已设置开机自启' : '已取消开机自启');
    return true;
  } catch (e) {
    EnodeLog.w('autostart', '${enable ? '设置' : '取消'}开机自启失败', e);
    return false;
  }
}
