import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/l10n/l10n.dart';

export 'package:b_player/l10n/l10n.dart';

/// 测试统一跑繁体中文（简体/繁中/英文三种文案里选繁中做基准）；
/// 同时把没有 BuildContext 的全局文案绑到同一语言，状态/错误断言才不会串语言。
void useTraditionalChinese() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localesTestValue = const [zhHantLocale];
  addTearDown(binding.platformDispatcher.clearLocalesTestValue);
  bindL10n(zhHantLocale);
}

/// 给不用 BPlayerApp 的测试：自带本地化代理并固定繁体中文。
Widget localizedApp({required Widget home, ThemeData? theme}) => MaterialApp(
      locale: zhHantLocale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      theme: theme,
      home: home,
    );
