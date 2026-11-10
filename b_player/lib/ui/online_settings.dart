import 'dart:async';

import 'package:flutter/material.dart';

import '../edge/sources/lx_config.dart';
import '../edge/sources/lx_script_runtime.dart';
import '../edge/sources/lx_settings.dart';
import '../edge/sources/lx_source_entry.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'cards.dart';
import 'form_bits.dart';

/// 在线音源管理：导入脚本、启停/排序/测试，以及音质设置。
class OnlineSourcesPanel extends StatefulWidget {
  const OnlineSourcesPanel({super.key, required this.state});
  final AppState state;

  @override
  State<OnlineSourcesPanel> createState() => _OnlineSourcesPanelState();
}

class _OnlineSourcesPanelState extends State<OnlineSourcesPanel> {
  late final TextEditingController _importUrl;
  late String _quality;
  late List<LxSourceEntry> _sources;

  final Map<String, String> _testResults = {};
  final Set<String> _testOk = {};
  final Set<String> _testing = {};

  final Set<String> _checking = {};
  final Map<String, LxSourceEntry> _pendingUpdates = {};
  final Map<String, String> _updateNotes = {};
  final Map<String, String> _updateErrors = {};

  bool _importing = false;
  String? _error;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    final initial = widget.state.onlineSettings ?? LxSettings.defaults;
    _importUrl = TextEditingController();
    _quality = initial.quality;
    _sources = [...widget.state.onlineSources];
  }

  @override
  void dispose() {
    _importUrl.dispose();
    super.dispose();
  }

  /// 页面上任何改动都立刻写盘并热更新到运行时，不再需要「再点一次保存」。
  Future<void> _persist({String? done}) async {
    try {
      await widget.state.saveOnlineSettings(LxSettings(
        quality: _quality,
        enabledPlatforms: LxSettings.defaults.enabledPlatforms,
      ));
      await widget.state.saveOnlineSources(_sources);
      if (!mounted) return;
      if (done != null) setState(() => _feedback = done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.saveFailed('$e'));
    }
  }

  Future<void> _import() async {
    final url = _importUrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = l10n.needSourceUrl);
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final entry = await fetchLxSource(url);
      if (!mounted) return;
      setState(() {
        _sources = LxSourceStore.upsert(_sources, entry);
        _importUrl.clear();
        _pendingUpdates.remove(entry.id);
        _updateNotes.remove(entry.id);
        _updateErrors.remove(entry.id);
      });
      await _persist(done: l10n.importedCount(_sources.length));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.importFailedOnline('$e'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 单个音源的完整自检：脚本握手 + 走一次真实检索与取链。
  Future<void> _test(LxSourceEntry entry) async {
    setState(() {
      _testing.add(entry.id);
      _testResults.remove(entry.id);
    });
    final probed = await widget.state.testOnlineSource(entry);
    final online = probed.ok ? await widget.state.probeOnlineSearch() : null;
    if (!mounted) return;
    setState(() {
      _testing.remove(entry.id);
      if (probed.ok) {
        _testOk.add(entry.id);
      } else {
        _testOk.remove(entry.id);
      }
      _testResults[entry.id] = online == null ? probed.message : '${probed.message} · $online';
      final note = _noticeOf(probed.alert);
      if (note != null) _updateNotes[entry.id] = note;
    });
  }

  String? _noticeOf(LxUpdateAlert? alert) {
    if (alert == null) return null;
    final lines = <String>[
      if (alert.log.trim().isNotEmpty) l10n.sourceNotice(alert.log.trim()),
      if (alert.url.isNotEmpty) l10n.sourceNoticeLink(alert.url),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// 只重新下载比对，不自动替换；新脚本要用户点「更新」才会执行。
  Future<void> _checkUpdate(LxSourceEntry entry) async {
    final id = entry.id;
    setState(() {
      _checking.add(id);
      _pendingUpdates.remove(id);
      _updateNotes.remove(id);
      _updateErrors.remove(id);
      _feedback = null;
    });
    final result = await widget.state.checkOnlineSourceUpdate(entry);
    if (!mounted) return;
    setState(() {
      _checking.remove(id);
      if (result.error != null) {
        _updateErrors[id] = result.error!;
        return;
      }
      final latest = result.update;
      if (latest != null) _pendingUpdates[id] = latest;
      final note = _noticeOf(result.alert);
      if (note != null) {
        _updateNotes[id] = note;
      } else if (latest == null) {
        final version = entry.versionLabel;
        _updateNotes[id] =
            version.isEmpty ? l10n.sourceUpToDate : '${l10n.sourceUpToDate} · $version';
      }
    });
  }

  void _applyUpdate(LxSourceEntry latest) {
    setState(() {
      _sources = LxSourceStore.upsert(_sources, latest);
      _pendingUpdates.remove(latest.id);
      _updateNotes.remove(latest.id);
      _updateErrors.remove(latest.id);
      _testResults.remove(latest.id);
      _testOk.remove(latest.id);
    });
    final version = latest.versionLabel;
    unawaited(_persist(
      done: version.isEmpty ? l10n.sourceUpdatedPlain : l10n.sourceUpdated(version),
    ));
  }

  void _dismissUpdate(String id) {
    setState(() {
      _pendingUpdates.remove(id);
      _updateNotes.remove(id);
      _updateErrors.remove(id);
    });
  }

  void _toggle(String id, bool enabled) {
    setState(() {
      _sources = [
        for (final source in _sources)
          source.id == id ? source.copyWith(enabled: enabled) : source,
      ];
    });
    unawaited(_persist(done: enabled ? l10n.sourceEnabled : l10n.sourceDisabled));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _sources.length) return;
    setState(() {
      final next = [..._sources];
      final item = next.removeAt(index);
      next.insert(target, item);
      _sources = next;
    });
    unawaited(_persist(done: l10n.sourceOrderUpdated));
  }

  void _removeAt(int index) {
    final id = _sources[index].id;
    setState(() {
      _sources = [..._sources]..removeAt(index);
      _testResults.remove(id);
      _testOk.remove(id);
      _pendingUpdates.remove(id);
      _updateNotes.remove(id);
      _updateErrors.remove(id);
      _checking.remove(id);
    });
    unawaited(_persist(done: l10n.sourceRemoved));
  }

  void _resetDefaults() {
    setState(() {
      _quality = LxSettings.defaults.quality;
      _testResults.clear();
      _testOk.clear();
      _checking.clear();
      _pendingUpdates.clear();
      _updateNotes.clear();
      _updateErrors.clear();
      _error = null;
      _feedback = null;
    });
    unawaited(_persist(done: l10n.defaultsRestored));
  }

  String _statusOf(LxSourceEntry source) {
    final tested = _testResults[source.id];
    if (tested != null) return tested;
    final error = source.lastError;
    if (error != null && error.trim().isNotEmpty) return l10n.statusError(error);
    final subtitle = source.subtitle;
    return subtitle.isEmpty ? source.url : '$subtitle · ${source.url}';
  }

  Color _statusColor(LxSourceEntry source) {
    if (_testResults.containsKey(source.id)) return _testOk.contains(source.id) ? C.acc : C.bad;
    final error = source.lastError;
    return error == null || error.trim().isEmpty ? C.faint : C.bad;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHead(t.onlineSourcesTitle, trailing: t.scriptCount(_sources.length)),
            Text(t.sourcesIntro, style: kMini),
            const SizedBox(height: 14),
            if (_sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(t.sourcesEmpty,
                    style: TextStyle(fontSize: 11.5, color: C.faint)),
              )
            else
              for (var i = 0; i < _sources.length; i++) _sourceRow(i),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: FormInput(
                  controller: _importUrl,
                  hint: t.importHint,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _importing ? null : _import,
                style: FilledButton.styleFrom(
                  backgroundColor: C.acc,
                  foregroundColor: C.onAcc,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_importing ? t.importing : t.importAction),
              ),
            ]),
            if (_feedback != null) ...[
              const SizedBox(height: 6),
              Text(_feedback!, style: TextStyle(fontSize: 11, color: C.acc)),
            ],
            const SizedBox(height: 14),
            FieldLabel(t.qualityLabel),
            const SizedBox(height: 7),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in lxQualityOptions)
                Choice(
                  label: q,
                  on: q == _quality,
                  onTap: () {
                    setState(() {
                      _quality = q;
                      _error = null;
                    });
                    unawaited(_persist(done: l10n.qualitySaved));
                  },
                ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: C.bad)),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _resetDefaults,
                child: Text(t.restoreDefaults,
                    style: TextStyle(color: C.dim, fontSize: 12)),
              ),
            ),
          ],
        ),
      );
  }

  Widget _busy() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: C.acc),
        ),
      );

  Widget _updatePanel(LxSourceEntry source) {
    final pending = _pendingUpdates[source.id];
    final note = _updateNotes[source.id];
    final error = _updateErrors[source.id];
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 4, right: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (pending != null)
          Row(children: [
            Expanded(
              child: Text(
                l10n.sourceUpdateFound(
                  pending.versionLabel.isEmpty ? pending.name : pending.versionLabel,
                  source.versionLabel.isEmpty ? '—' : source.versionLabel,
                ),
                style: TextStyle(fontSize: 11, color: C.warn),
              ),
            ),
            _LinkBtn(
              label: l10n.sourceUpdateApply,
              onPressed: () => _applyUpdate(pending),
            ),
            _LinkBtn(
              label: l10n.sourceUpdateDismiss,
              onPressed: () => _dismissUpdate(source.id),
            ),
          ]),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: C.acc, height: 1.35),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.updateCheckFailed(error),
              style: TextStyle(fontSize: 10.5, color: C.bad),
            ),
          ),
      ]),
    );
  }

  Widget _sourceRow(int index) {
    final source = _sources[index];
    final testing = _testing.contains(source.id);
    final checking = _checking.contains(source.id);
    final hasUpdateState = _pendingUpdates.containsKey(source.id) ||
        _updateNotes.containsKey(source.id) ||
        _updateErrors.containsKey(source.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: C.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: C.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Checkbox(
            value: source.enabled,
            onChanged: (value) => _toggle(source.id, value ?? false),
            activeColor: C.acc,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: source.enabled ? C.txt : C.dim,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _statusOf(source),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: _statusColor(source)),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.arrow_upward_rounded,
            tooltip: l10n.moveUp,
            onPressed: index == 0 ? null : () => _move(index, -1),
          ),
          _IconBtn(
            icon: Icons.arrow_downward_rounded,
            tooltip: l10n.moveDown,
            onPressed: index == _sources.length - 1 ? null : () => _move(index, 1),
          ),
          if (testing)
            _busy()
          else
            _IconBtn(
              icon: Icons.bolt_rounded,
              tooltip: l10n.testSourceTooltip,
              onPressed: () => _test(source),
            ),
          if (checking)
            _busy()
          else
            _IconBtn(
              icon: Icons.sync_rounded,
              tooltip: l10n.checkSourceUpdate,
              onPressed: () => _checkUpdate(source),
            ),
          _IconBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: l10n.delete,
            onPressed: () => _removeAt(index),
          ),
        ]),
        if (hasUpdateState) _updatePanel(source),
      ]),
    );
  }
}

class _LinkBtn extends StatelessWidget {
  const _LinkBtn({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: C.acc,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 26),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(label),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        iconSize: 17,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        color: C.dim,
        disabledColor: C.line,
        tooltip: tooltip,
        icon: Icon(icon),
      );
}
