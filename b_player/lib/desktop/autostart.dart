import 'dart:io';

/// 开机自启：写当前用户的 Run 键，不需要管理员权限。
/// 值必须带引号，因为安装目录 `C:\Program Files\eNode` 里有空格。
const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _runValue = 'eNode';

Future<bool> isAutostartEnabled() async =>
    (await Process.run('reg.exe', [
      'query',
      _runKey,
      '/v',
      _runValue,
    ])).exitCode ==
    0;

Future<void> setAutostart(bool enable) async {
  if (enable) {
    await Process.run('reg.exe', [
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
  } else {
    await Process.run('reg.exe', ['delete', _runKey, '/v', _runValue, '/f']);
  }
}
