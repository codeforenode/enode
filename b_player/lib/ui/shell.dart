import 'dart:async';

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../edge/edge_node.dart';
import '../l10n/l10n.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../state/app_update.dart';
import '../theme.dart';
import 'cards.dart';
import 'settings_dialog.dart';
import 'sources_panel.dart';
import 'update_bits.dart';

/// 一屏外壳：顶栏状态 · 上区播放与队列 · 底部音源区，没有标签页。
class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.state,
    required this.settings,
    this.updates,
  });
  final AppState state;
  final AppSettings settings;

  /// 应用更新检查；演示/测试模式为 null，不联网也不显示入口。
  final AppUpdateController? updates;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  /// 在线音源段只在本次运行内解锁，重启即恢复隐藏。
  bool _onlineUnlocked = false;

  /// 启动检查只自动弹一次；之后手动检查的结果留在「关于」里。
  bool _updatePrompted = false;

  @override
  void initState() {
    super.initState();
    final updates = widget.updates;
    if (updates == null) return;
    updates.addListener(_onUpdateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(updates.check());
    });
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_onUpdateChanged);
    super.dispose();
  }

  void _onUpdateChanged() {
    final release = widget.updates?.available;
    if (!mounted || release == null || _updatePrompted) return;
    _updatePrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showAppUpdateDialog(context, release));
    });
  }

  void _unlockOnline() => _onlineUnlocked = true;

  void _openSettings() => showSettings(
        context,
        state: widget.state,
        settings: widget.settings,
        updates: widget.updates,
        onlineUnlocked: _onlineUnlocked,
        onUnlockOnline: _unlockOnline,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 900 ? _wide() : _narrow(),
          ),
        ),
      );

  Widget _wide() => Column(children: [
        _TopBar(
          state: widget.state,
          settings: widget.settings,
          onSettings: _openSettings,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                flex: 100,
                child: SingleChildScrollView(child: NowPlayingCard(state: widget.state)),
              ),
              const SizedBox(width: 14),
              Expanded(flex: 130, child: QueueCard(state: widget.state)),
            ]),
          ),
        ),
        SizedBox(
          height: 190,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SourcesPanel(state: widget.state),
          ),
        ),
      ]);

  Widget _narrow() => Column(children: [
        _BrandBar(
          state: widget.state,
          onSettings: _openSettings,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              SingleChildScrollView(child: NowPlayingCard(state: widget.state, compact: true)),
              const SizedBox(height: 10),
              Expanded(child: QueueCard(state: widget.state, compact: true)),
            ]),
          ),
        ),
        SourcesStrip(state: widget.state),
      ]);
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.settings,
    required this.onSettings,
  });
  final AppState state;
  final AppSettings settings;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: C.top,
          border: Border(bottom: BorderSide(color: C.line)),
        ),
        child: Row(children: [
          const _Brand(),
          const SizedBox(width: 14),
          _Status(state: state),
          const Spacer(),
          const _VersionBadge(),
          const SizedBox(width: 2),
          _SettingsButton(onSettings: onSettings),
        ]),
      );
}

/// 窄屏顶栏：品牌省略，状态与入口靠右。
class _BrandBar extends StatelessWidget {
  const _BrandBar({
    required this.state,
    required this.onSettings,
  });
  final AppState state;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
        child: Row(children: [
          const Spacer(),
          _Status(state: state),
          const SizedBox(width: 4),
          const _VersionBadge(),
          _SettingsButton(onSettings: onSettings),
        ]),
      );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: C.acc,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.music_note_rounded, size: 13, color: C.onAcc),
    ),
    const SizedBox(width: 8),
    Text('eNode', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.txt)),
  ]);
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final edge = state.edge;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Dot(on: edge.connected),
      const SizedBox(width: 6),
      Text(
        edge.statusLabel,
        style: TextStyle(
          fontSize: 11.5,
          color: edge.status == EdgeStatus.error ? C.bad : C.dim,
        ),
      ),
      if (edge.nodeId.isNotEmpty) ...[
        const SizedBox(width: 10),
        Text(edge.nodeId, style: kNums.copyWith(fontSize: 11, color: C.faint)),
      ],
    ]);
  }
}

/// 版本号只做展示；在线音源的解锁入口在「设置 → 关于」的版本行。
class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text('v$appVersion', style: kNums.copyWith(fontSize: 10.5, color: C.faint)),
      );
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onSettings,
        iconSize: 19,
        visualDensity: VisualDensity.compact,
        color: C.dim,
        tooltip: l10n.settingsTooltip,
        icon: const Icon(Icons.settings_rounded),
      );
}
