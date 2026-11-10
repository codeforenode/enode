import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'autostart.dart';
import '../l10n/l10n.dart';

/// Windows 桌面常驻：托盘图标 + 关窗收进托盘 + 开机自启 + 退出确认。
class WindowsHost with TrayListener, WindowListener {
  WindowsHost(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  /// 退出前收尾（断开 MQTT、停引擎），由 AppState 注入。
  Future<void> Function()? onBeforeExit;

  bool _exiting = false;

  static const _openKey = 'open';
  static const _autostartKey = 'autostart';
  static const _quitKey = 'quit';

  Future<void> start() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icons/enode.ico');
    await trayManager.setToolTip('eNode');
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final autostart = await isAutostartEnabled();
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _openKey, label: l10n.trayOpen),
          MenuItem.checkbox(
            key: _autostartKey,
            label: l10n.trayAutostart,
            checked: autostart,
          ),
          MenuItem.separator(),
          MenuItem(key: _quitKey, label: l10n.trayQuit),
        ],
      ),
    );
  }

  /// 语言切换后重建托盘菜单，文字跟着变。
  Future<void> refreshMenu() => _rebuildMenu();

  Future<void> showWindow() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _openKey:
        unawaited(showWindow());
      case _autostartKey:
        unawaited(_toggleAutostart(!(menuItem.checked ?? false)));
      case _quitKey:
        unawaited(quit());
    }
  }

  Future<void> _toggleAutostart(bool enable) async {
    await setAutostart(enable);
    await _rebuildMenu();
  }

  /// 点标题栏的叉只是收进托盘，播放与点歌服务继续跑。
  @override
  void onWindowClose() => unawaited(windowManager.hide());

  Future<void> quit() async {
    if (_exiting) return;
    _exiting = true;
    await showWindow();
    if (!await _confirmExit()) {
      _exiting = false;
      return;
    }
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await onBeforeExit?.call();
    exit(0);
  }

  Future<bool> _confirmExit() async {
    final context = navigatorKey.currentContext;
    if (context == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exitTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.trayQuit),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
