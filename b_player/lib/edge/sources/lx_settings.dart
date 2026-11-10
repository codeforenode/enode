import 'package:shared_preferences/shared_preferences.dart';

import 'lx_config.dart';

/// 在线音源的运行配置：音质与可用平台。
///
/// 平台不提供用户开关：默认全开，实际能搜到哪些曲目由导入的脚本决定。
/// 播放地址不内置任何兜底服务，只使用用户导入的音源脚本。
class LxSettings {
  const LxSettings({
    required this.quality,
    required this.enabledPlatforms,
  });

  static const defaults = LxSettings(
    quality: lxDefaultQuality,
    enabledPlatforms: lxDefaultPlatformIds,
  );

  static const _qualityKey = 'lx.quality';

  // 旧版按平台勾选时写下的键，仅用于清理残留。
  static const _legacyPlatformsKey = 'lx.platforms';

  // 旧版内置兜底服务的地址/密钥，仅用于清理残留。
  static const _legacyBaseKey = 'lx.apiBase';
  static const _legacyApiKey = 'lx.apiKey';

  final String quality;
  final Set<String> enabledPlatforms;

  List<String> get enabledPlatformIds => [
        for (final id in lxPlatformCatalog)
          if (enabledPlatforms.contains(id)) id,
      ];

  static Future<LxSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return LxSettings(
        quality: lxQualityOptions.contains(p.getString(_qualityKey))
            ? p.getString(_qualityKey)!
            : defaults.quality,
        enabledPlatforms: defaults.enabledPlatforms,
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_legacyBaseKey);
      await p.remove(_legacyApiKey);
      await p.remove(_legacyPlatformsKey);
      await p.setString(_qualityKey, quality);
    } catch (_) {
      // 无插件环境（单元测试/桌面预览）下不阻断保存流程。
    }
  }

  LxSettings copyWith({
    String? quality,
    Set<String>? enabledPlatforms,
  }) =>
      LxSettings(
        quality: quality ?? this.quality,
        enabledPlatforms: enabledPlatforms ?? this.enabledPlatforms,
      );
}
