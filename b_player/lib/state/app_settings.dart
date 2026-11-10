import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextSize {
  small(0.9),
  medium(1.0),
  large(1.15),
  xlarge(1.3);

  const TextSize(this.scale);
  final double scale;
}

enum AppLanguage {
  system(null, 'system'),
  simplifiedChinese(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), 'zh_Hans'),
  traditionalChinese(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 'zh_Hant'),
  english(Locale('en'), 'en');

  const AppLanguage(this.locale, this.code);

  /// null 表示跟随系统：系统是中文就按书写系统/地区分简繁，其余落到英文。
  final Locale? locale;
  final String code;

  static AppLanguage fromCode(String? code) =>
      values.firstWhere((lang) => lang.code == code, orElse: () => system);
}

/// 只包含显示偏好（主题、字号、语言），与 MQTT 参数无关；偏好保存在本机。
class AppSettings extends ChangeNotifier {
  static const _themeKey = 'ui.themeMode';
  static const _textKey = 'ui.textSize';
  static const _languageKey = 'ui.language';

  ThemeMode themeMode = ThemeMode.dark;
  TextSize textSize = TextSize.medium;
  AppLanguage language = AppLanguage.system;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = switch (p.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      final saved = p.getString(_textKey);
      textSize = TextSize.values.firstWhere((t) => t.name == saved, orElse: () => TextSize.medium);
      language = AppLanguage.fromCode(p.getString(_languageKey));
    } catch (_) {
      // 无插件环境：使用默认值。
    }
    notifyListeners();
  }

  void setTheme(ThemeMode mode) {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    _save(_themeKey, mode.name);
  }

  void setTextSize(TextSize size) {
    if (textSize == size) return;
    textSize = size;
    notifyListeners();
    _save(_textKey, size.name);
  }

  void setLanguage(AppLanguage lang) {
    if (language == lang) return;
    language = lang;
    notifyListeners();
    _save(_languageKey, lang.code);
  }

  void _save(String key, String value) {
    try {
      SharedPreferences.getInstance()
          .then((p) => p.setString(key, value))
          .catchError((_) => false);
    } catch (_) {}
  }
}
