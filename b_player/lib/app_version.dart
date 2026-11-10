import 'package:package_info_plus/package_info_plus.dart';

/// 界面显示的版本号，来源是 pubspec.yaml 的 version（打包时写进各平台的包信息）。
/// [loadAppVersion] 在 runApp 之前调用，所以首帧就是真实版本；初值只是兜底。
String appVersion = 'dev';

Future<void> loadAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.isNotEmpty) appVersion = info.version;
}
