import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:b_player/l10n/l10n.dart';
import 'package:b_player/state/app_settings.dart';

void main() {
  group('语言解析：中文按书写系统/地区分简繁，其余英文', () {
    test('简中系统落到简体中文', () {
      for (final locale in const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'SG'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'MY'),
      ]) {
        expect(resolveAppLocale(null, deviceLocales: [locale]), zhHansLocale,
            reason: '$locale 应显示简体中文');
      }
    });

    test('繁中系统（含无地区中文）落到繁体中文', () {
      for (final locale in const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'HK'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'MO'),
        Locale('zh'),
      ]) {
        expect(resolveAppLocale(null, deviceLocales: [locale]), zhHantLocale,
            reason: '$locale 应显示繁体中文');
      }
    });

    test('非中文系统落到英文', () {
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ja'),
        Locale('de'),
        Locale('fr', 'FR'),
      ]) {
        expect(resolveAppLocale(null, deviceLocales: [locale]), const Locale('en'),
            reason: '$locale 应显示英文');
      }
    });

    test('手动选择优先于系统', () {
      expect(resolveAppLocale(AppLanguage.english.locale, deviceLocales: const [Locale('zh')]),
          const Locale('en'));
      expect(resolveAppLocale(AppLanguage.simplifiedChinese.locale,
          deviceLocales: const [Locale('zh', 'TW')]), zhHansLocale);
      expect(resolveAppLocale(AppLanguage.traditionalChinese.locale,
          deviceLocales: const [Locale('zh', 'CN')]), zhHantLocale);
    });

    test('投放子引擎的 BCP-47 标签能还原语言', () {
      expect(localeForTag('zh-Hans'), zhHansLocale);
      expect(localeForTag('zh-Hant'), zhHantLocale);
      expect(localeForTag('zh-Hans-CN'), zhHansLocale);
      expect(localeForTag('zh-Hant-TW'), zhHantLocale);
      expect(localeForTag('en'), const Locale('en'));
    });
  });

  test('语言偏好写入 ui.language，重启后恢复', () async {
    SharedPreferences.setMockInitialValues({'ui.language': 'en'});
    final settings = AppSettings();
    await settings.load();
    expect(settings.language, AppLanguage.english);

    settings.setLanguage(AppLanguage.simplifiedChinese);
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui.language'), 'zh_Hans');

    settings.setLanguage(AppLanguage.traditionalChinese);
    await pumpEventQueue();
    expect(prefs.getString('ui.language'), 'zh_Hant');

    settings.dispose();
  });
}
