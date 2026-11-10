import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String appLicenseName = 'AGPL-3.0';
const String appCopyright = '© 2026 eNode contributors';

/// 公开仓库地址；为空时界面不显示源码入口。
const String appSourceUrl = 'https://github.com/codeforenode/enode';

/// 把 AGPL 全文与第三方声明注入 Flutter 的许可证页。
/// 文本随 assets 打包，Android 安装包里也能查看。
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['eNode'],
      await rootBundle.loadString('assets/legal/LICENSE'),
    );
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['eNode third-party components'],
      await rootBundle.loadString('assets/legal/THIRD_PARTY_NOTICES.md'),
    );
  });
}
