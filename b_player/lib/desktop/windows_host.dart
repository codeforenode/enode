import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'autostart.dart';
import '../l10n/l10n.dart';
import '../log.dart';

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
  void onTrayIconMouseDown() => _guard('托盘单击', () => unawaited(showWindow()));

  @override
  void onTrayIconRightMouseDown() => _guard('托盘右键', () => unawaited(trayManager.popUpContextMenu()));

  /// 托盘与窗口事件都是**原生回调**：异常从这里逃出去会变成
  /// `0xc000041d STATUS_FATAL_USER_CALLBACK_EXCEPTION`（WER 只报 flutter_windows.dll，
  /// 看不出是哪一步）。所以每个入口先包一层，宁可少做一件事也不能让进程消失。
  void _guard(String what, void Function() body) {
    try {
      body();
    } catch (e, st) {
      EnodeLog.e('tray', '$what 回调失败', e, st);
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) => _guard('托盘菜单 ${menuItem.key}', () {
        switch (menuItem.key) {
          case _openKey:
            unawaited(showWindow());
          case _autostartKey:
            unawaited(_toggleAutostart(!(menuItem.checked ?? false)));
          case _quitKey:
            unawaited(quit());
        }
      });

  Future<void> _toggleAutostart(bool enable) async {
    await setAutostart(enable);
    await _rebuildMenu();
  }

  /// 点标题栏的叉只是收进托盘，播放与点歌服务继续跑。
  @override
  void onWindowClose() => _guard('关窗', () => unawaited(windowManager.hide()));

  Future<void> quit() async {
    if (_exiting) return;
    _exiting = true;
    EnodeLog.i('app', '退出：用户请求');
    await _guardAsync('显示主窗', showWindow);
    if (!await _confirmExit()) {
      _exiting = false;
      EnodeLog.i('app', '退出：已取消');
      return;
    }
    // 逐段留痕：退出崩溃时最后一行日志就是崩在哪一步。
    await _guardAsync('允许关窗', () => windowManager.setPreventClose(false));
    await _guardAsync('销毁托盘图标', trayManager.destroy);
    await _guardAsync('收尾（收投放窗/断 MQTT）', () async {
      await onBeforeExit?.call();
    });
    EnodeLog.i('app', '退出：收尾完成，结束进程');
    // 正常退出：撤掉运行标记，下次启动才不会误报「上次未正常退出」。
    await EnodeLog.markCleanExit();
    // 缓冲里还有几行没落盘，exit 会直接杀掉进程——先把日志刷出去。
    await EnodeLog.close();
    exit(0);
  }

  Future<void> _guardAsync(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      EnodeLog.e('app', '退出：$what 失败', e, st);
    }
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
