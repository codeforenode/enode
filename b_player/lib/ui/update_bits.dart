import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../l10n/l10n.dart';
import '../state/app_update.dart';
import '../theme.dart';

/// 打开更新下载页；失败时给一条提示，不打断当前操作。
Future<void> openAppLink(BuildContext context, String url) async {
  final t = AppL10n.of(context);
  final uri = Uri.tryParse(url);
  var opened = false;
  if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.openLinkFailed)));
  }
}

/// 启动时发现新版本的提示；确认后去下载，稍后关闭。
Future<void> showAppUpdateDialog(BuildContext context, AppRelease release) async {
  final t = AppL10n.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: C.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.updateAvailableTitle(release.tag),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.txt)),
          const SizedBox(height: 6),
          Text(t.updateAvailableBody('v$appVersion'),
              style: TextStyle(fontSize: 12.5, color: C.dim)),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.updateLater, style: TextStyle(color: C.dim)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
              child: Text(t.updateDownload),
            ),
          ]),
        ]),
      ),
    ),
  );
  if (go == true && context.mounted) await openAppLink(context, release.downloadUrl);
}
