import 'package:flutter/widgets.dart';

import 'app_l10n.dart';

export 'app_l10n.dart';

/// 产品只提供三种界面语言：简体中文、繁体中文、英文。
const Locale zhHantLocale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
const Locale zhHansLocale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

/// 中文按书写系统（或地区）分简繁；没有脚本/地区的中文沿用旧行为落到繁中。
Locale resolveAppLocale(Locale? override, {List<Locale>? deviceLocales}) {
  if (override != null) return _chineseVariant(override) ?? override;
  final preferred = deviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
  for (final locale in preferred) {
    if (locale.languageCode == 'zh') return _chineseVariant(locale) ?? zhHantLocale;
  }
  return basicLocaleListResolution(preferred, AppL10n.supportedLocales);
}

Locale? _chineseVariant(Locale locale) {
  if (locale.languageCode != 'zh') return null;
  if (locale.scriptCode == 'Hans') return zhHansLocale;
  if (locale.scriptCode == 'Hant') return zhHantLocale;
  const simplifiedRegions = {'CN', 'SG', 'MY'};
  const traditionalRegions = {'TW', 'HK', 'MO'};
  if (simplifiedRegions.contains(locale.countryCode)) return zhHansLocale;
  if (traditionalRegions.contains(locale.countryCode)) return zhHantLocale;
  return zhHantLocale;
}

/// 解析投放载荷里的 BCP-47 标签（zh-Hans / zh-Hant / en）。
Locale localeForTag(String tag) {
  final parts = tag.split(RegExp(r'[-_]'));
  if (parts.isEmpty || parts.first.isEmpty) return const Locale('en');
  String? script;
  String? country;
  for (final part in parts.skip(1)) {
    if (part.length == 4) {
      script = part[0].toUpperCase() + part.substring(1).toLowerCase();
    } else if (part.length == 2 || part.length == 3) {
      country = part.toUpperCase();
    }
  }
  return resolveAppLocale(Locale.fromSubtags(
    languageCode: parts.first.toLowerCase(),
    scriptCode: script,
    countryCode: country,
  ));
}

AppL10n _current = lookupAppL10n(zhHantLocale);
Locale _currentLocale = zhHantLocale;

/// 给拿不到 BuildContext 的代码用（托盘、投放子引擎、状态/错误文案）。
/// 语言切换时由 BPlayerApp 重新绑定。
AppL10n get l10n => _current;

Locale get currentLocale => _currentLocale;

void bindL10n(Locale locale) {
  _currentLocale = locale;
  _current = lookupAppL10n(locale);
}
