import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../edge/edge_node.dart';
import '../l10n/l10n.dart';
import '../legal.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../state/app_update.dart';
import '../theme.dart';
import 'form_bits.dart';
import 'mqtt_panel.dart';
import 'online_settings.dart';
import 'screen_cast_panel.dart';
import 'secret_tap.dart';
import 'update_bits.dart';

enum _Tab { display, broadcast, sources, cast, about }

/// 铺满窗口的设置页：头部与等宽设置项固定，切换只替换内容区，窗口尺寸不变。
/// 「音源」段由「关于」里的版本号解锁，未解锁时整段不出现。
Future<void> showSettings(
  BuildContext context, {
  required AppState state,
  required AppSettings settings,
  AppUpdateController? updates,
  required bool onlineUnlocked,
  required VoidCallback onUnlockOnline,
}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => _SettingsPage(
          state: state,
          settings: settings,
          updates: updates,
          onlineUnlocked: onlineUnlocked,
          onUnlockOnline: onUnlockOnline,
        ),
      ),
    );

const double _tabWidth = 110;
const double _tabGap = 8;
const double _navPad = 16;

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.state,
    required this.settings,
    required this.updates,
    required this.onlineUnlocked,
    required this.onUnlockOnline,
  });
  final AppState state;
  final AppSettings settings;
  final AppUpdateController? updates;
  final bool onlineUnlocked;
  final VoidCallback onUnlockOnline;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late bool _unlocked = widget.onlineUnlocked;
  late _Tab _tab = _unlocked ? _Tab.sources : _Tab.display;

  void _openSources() {
    final wasUnlocked = _unlocked;
    setState(() {
      _unlocked = true;
      _tab = _Tab.sources;
    });
    if (!wasUnlocked) widget.onUnlockOnline();
  }

  void _close() => Navigator.of(context).maybePop();

  List<_Tab> get _tabs => [
        _Tab.display,
        _Tab.broadcast,
        if (_unlocked) _Tab.sources,
        // 投放入口跟着真实能力走：非 Windows、或一台显示器都没扫到时整段不出现。
        if (Platform.isWindows && widget.state.castMonitors.isNotEmpty) _Tab.cast,
        _Tab.about,
      ];

  String _tabLabel(AppL10n t, _Tab tab) => switch (tab) {
        _Tab.display => t.tabDisplay,
        _Tab.broadcast => t.tabBroadcast,
        _Tab.sources => t.tabSources,
        _Tab.cast => t.tabCast,
        _Tab.about => t.tabAbout,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    if (!_tabs.contains(_tab)) _tab = _Tab.display;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: C.bg,
          body: SafeArea(
            child: Column(children: [
              _header(t),
              _nav(t),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: SizedBox.expand(child: _pane(t)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(AppL10n t) => SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _navPad),
          child: Row(children: [
            Icon(Icons.settings_rounded, size: 17, color: C.acc),
            const SizedBox(width: 8),
            Text(t.settingsTitle,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.txt)),
            const Spacer(),
            FilledButton(
              onPressed: _close,
              style: FilledButton.styleFrom(
                backgroundColor: C.acc,
                foregroundColor: C.onAcc,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(t.done),
            ),
          ]),
        ),
      );

  /// 等宽固定 110px；窗口窄到放不下时退化成均分，保证每个设置项都点得到。
  Widget _nav(AppL10n t) => LayoutBuilder(builder: (context, box) {
        final tabs = _tabs;
        final fixed = box.maxWidth >=
            tabs.length * _tabWidth + (tabs.length - 1) * _tabGap + _navPad * 2;
        return Container(
          height: 44,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
          padding: const EdgeInsets.symmetric(horizontal: _navPad),
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0 && fixed) const SizedBox(width: _tabGap),
              if (fixed)
                SizedBox(width: _tabWidth, child: _tabButton(t, tabs[i]))
              else
                Expanded(child: _tabButton(t, tabs[i])),
            ],
          ]),
        );
      });

  Widget _tabButton(AppL10n t, _Tab tab) {
    final on = tab == _tab;
    return InkWell(
      onTap: () => setState(() => _tab = tab),
      hoverColor: C.panel2,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? C.acc : Colors.transparent, width: 2)),
        ),
        child: Text(
          _tabLabel(t, tab),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? C.acc : C.dim,
          ),
        ),
      ),
    );
  }

  Widget _pane(AppL10n t) => switch (_tab) {
        _Tab.cast => Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: ScreenCastPanel(state: widget.state),
          ),
        _Tab.display => _scrolled(
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _Display(settings: widget.settings),
            ),
          ),
        _Tab.broadcast => _scrolled(
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: MqttPanel(state: widget.state),
            ),
          ),
        _Tab.sources => _scrolled(OnlineSourcesPanel(state: widget.state)),
        _Tab.about => _scrolled(
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _About(
                state: widget.state,
                updates: widget.updates,
                onOpenSources: _openSources,
              ),
            ),
          ),
      };

  Widget _scrolled(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(_navPad + 2, 16, _navPad + 2, 24),
        child: Align(alignment: Alignment.topLeft, child: child),
      );
}

class _Display extends StatelessWidget {
  const _Display({required this.settings});
  final AppSettings settings;

  static String _textSizeLabel(AppL10n t, TextSize size) => switch (size) {
        TextSize.small => t.textSizeSmall,
        TextSize.medium => t.textSizeMedium,
        TextSize.large => t.textSizeLarge,
        TextSize.xlarge => t.textSizeXLarge,
      };

  static String _languageLabel(AppL10n t, AppLanguage lang) => switch (lang) {
        AppLanguage.system => t.languageSystem,
        AppLanguage.simplifiedChinese => t.languageSimplifiedChinese,
        AppLanguage.traditionalChinese => t.languageTraditionalChinese,
        AppLanguage.english => t.languageEnglish,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final t = AppL10n.of(context);
          final themes = [
            (ThemeMode.dark, t.themeDark),
            (ThemeMode.light, t.themeLight),
            (ThemeMode.system, t.themeSystem),
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldLabel(t.theme),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final theme in themes)
                  Choice(
                    fill: C.panel,
                    label: theme.$2,
                    on: settings.themeMode == theme.$1,
                    onTap: () => settings.setTheme(theme.$1),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(t.themeSystemHint, style: kMini),
              const SizedBox(height: 16),
              FieldLabel(t.textSize),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final size in TextSize.values)
                  Choice(
                    fill: C.panel,
                    label: _textSizeLabel(t, size),
                    on: settings.textSize == size,
                    onTap: () => settings.setTextSize(size),
                  ),
              ]),
              const SizedBox(height: 16),
              FieldLabel(t.language),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final lang in AppLanguage.values)
                  Choice(
                    fill: C.panel,
                    label: _languageLabel(t, lang),
                    on: settings.language == lang,
                    onTap: () => settings.setLanguage(lang),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(t.languageHint, style: kMini),
              const SizedBox(height: 6),
              Text(t.displayPrefsHint, style: kMini),
            ],
          );
        },
      );
}

class _About extends StatelessWidget {
  const _About({required this.state, required this.updates, required this.onOpenSources});
  final AppState state;
  final AppUpdateController? updates;
  final VoidCallback onOpenSources;

  static String _updateText(AppL10n t, AppUpdateController u) => switch (u.status) {
        AppUpdateStatus.idle => t.aboutUpdateIdle,
        AppUpdateStatus.checking => t.aboutCheckingUpdate,
        AppUpdateStatus.latest => t.aboutUpToDate,
        AppUpdateStatus.available => t.aboutNewVersion(u.available!.tag),
        AppUpdateStatus.noRelease => t.aboutNoRelease,
        AppUpdateStatus.failed => t.updateCheckFailed(u.error ?? ''),
      };

  @override
  Widget build(BuildContext context) {
    final edge = state.edge;
    final t = AppL10n.of(context);
    final update = updates;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t.aboutVersionNode),
        const SizedBox(height: 8),
        SecretTap(
          key: const Key('aboutVersionTap'),
          onUnlock: onOpenSources,
          child: _Row(k: t.aboutVersion, v: 'v$appVersion'),
        ),
        if (update != null)
          ListenableBuilder(
            listenable: update,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  k: t.aboutUpdate,
                  v: _updateText(t, update),
                  warn: update.status == AppUpdateStatus.failed,
                ),
                Row(children: [
                  _link(
                    icon: Icons.sync_rounded,
                    label: t.aboutCheckUpdate,
                    onTap: () => unawaited(update.check()),
                  ),
                  if (update.available != null) ...[
                    const SizedBox(width: 16),
                    _link(
                      icon: Icons.download_rounded,
                      label: t.aboutDownloadUpdate,
                      onTap: () => unawaited(openAppLink(context, update.available!.downloadUrl)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        _Row(k: t.aboutNodeId, v: edge.nodeId.isEmpty ? t.notAssigned : edge.nodeId),
        _Row(
          k: t.aboutConnection,
          v: edge.statusLabel,
          warn: edge.status == EdgeStatus.error,
        ),
        _Row(k: t.aboutLibraryDir, v: state.scanDir.isEmpty ? t.notSet : state.scanDir),
        const SizedBox(height: 18),
        FieldLabel(t.aboutOpenSource),
        const SizedBox(height: 8),
        _Row(k: t.aboutLicense, v: appLicenseName),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(appCopyright, style: kNums.copyWith(fontSize: 12, color: C.txt)),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _link(
            icon: Icons.article_outlined,
            label: t.aboutViewLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'eNode',
              applicationVersion: 'v$appVersion',
              applicationLegalese: '$appLicenseName · $appCopyright',
            ),
          ),
          if (appSourceUrl.isNotEmpty)
            _link(
              icon: Icons.copy_rounded,
              label: t.aboutSourceCode,
              onTap: () async {
                await Clipboard.setData(const ClipboardData(text: appSourceUrl));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.aboutSourceCopied)),
                );
              },
            ),
        ]),
        const SizedBox(height: 6),
        Text(t.aboutOpenSourceHint, style: kMini),
      ],
    );
  }

  Widget _link({required IconData icon, required String label, required VoidCallback onTap}) =>
      TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: C.acc,
        ),
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.k, required this.v, this.warn = false});
  final String k;
  final String v;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 72, child: Text(k, style: TextStyle(fontSize: 11.5, color: C.dim))),
          Expanded(
            child: Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kNums.copyWith(
                    fontSize: 12, fontWeight: FontWeight.w600, color: warn ? C.bad : C.txt)),
          ),
        ]),
      );
}
