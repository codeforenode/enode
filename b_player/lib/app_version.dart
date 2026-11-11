import 'package:package_info_plus/package_info_plus.dart';

/// 界面显示的版本号，来源是 pubspec.yaml 的 version（打包时写进各平台的包信息）。
/// [loadAppVersion] 在 runApp 之前调用，所以首帧就是真实版本；初值只是兜底。
String appVersion = 'dev';

/// 构建号（pubspec 里的 `+10`）。判断「装的是不是同一个包」靠它，
/// 版本名相同、构建号不同的两份包天差地别，日志里必须能分开。
String appBuild = '';

/// 版本名 + 构建号，用于日志与关于页：`1.4.7+10`。
String get appVersionLabel => appBuild.isEmpty ? appVersion : '$appVersion+$appBuild';

Future<void> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) appVersion = info.version;
    appBuild = info.buildNumber;
  } catch (_) {
    // 读不到包信息（测试环境/插件异常）就保持 dev，不能让启动因此失败。
  }
}
