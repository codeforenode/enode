import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:b_player/legal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('随包许可证文本与仓库根文件保持一致', () {
    for (final name in const ['LICENSE', 'THIRD_PARTY_NOTICES.md']) {
      final repo = File('../$name').readAsStringSync();
      final asset = File('assets/legal/$name').readAsStringSync();
      expect(asset, repo, reason: '$name 修改后需要同步复制到 assets/legal/');
    }
  });

  testWidgets('许可证页包含 AGPL 全文与第三方声明', (tester) async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, contains('eNode'));
    expect(packages, contains('eNode third-party components'));

    final agpl = await rootBundle.loadString('assets/legal/LICENSE');
    expect(agpl, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
    final notices = await rootBundle.loadString('assets/legal/THIRD_PARTY_NOTICES.md');
    expect(notices, contains('libmpv'));
  });
}
