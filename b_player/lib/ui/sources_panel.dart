import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../edge/sources/webdav_config.dart';
import '../edge/sources/webdav_source.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'cards.dart';
import 'directory_picker.dart';
import 'form_bits.dart';

/// 音源区：本地目录 + WebDAV，两者扫出的曲目都进同一套检索/点歌/投放。
///
/// 宽屏固定在主界面底部一条；窄屏收成一行状态条，点开进整页管理。

class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final t = AppL10n.of(context);
          return Panel(
            key: const Key('sources-panel'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(t.sourcesTitle, style: kCardTitle),
                const SizedBox(width: 10),
                Text(t.sourcesTotal(state.libraryCount),
                    style: kNums.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: C.txt)),
                const Spacer(),
                Flexible(
                  child: Text(t.sourcesSummary(state.localTrackCount, state.webDavTrackCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMini),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 42,
                    child: SingleChildScrollView(child: _LocalBlock(state: state)),
                  ),
                  const SizedBox(width: 14),
                  Container(width: 1, color: C.line),
                  const SizedBox(width: 14),
                  Expanded(flex: 58, child: _WebDavBlock(state: state, dense: true)),
                ]),
              ),
            ]),
          );
        },
      );
}

class SourcesStrip extends StatelessWidget {
  const SourcesStrip({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final t = AppL10n.of(context);
          final syncing = state.webDavSources.any((s) => state.webDavSyncing(s.id));
          return Material(
            color: C.top,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () => showSourcesPage(context, state: state),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                child: Row(children: [
                  Icon(Icons.library_music_outlined, size: 16, color: C.acc),
                  const SizedBox(width: 8),
                  Text(t.sourcesTitle, style: kCardTitle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        syncing
                            ? t.webdavSyncing
                            : t.sourcesSummary(state.localTrackCount, state.webDavTrackCount),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.dim)),
                  ),
                  _MiniBtn(
                    key: const Key('sources-manage'),
                    label: t.manageSources,
                    icon: Icons.tune_rounded,
                    onTap: () => showSourcesPage(context, state: state),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

Future<void> showSourcesPage(BuildContext context, {required AppState state}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => _SourcesPage(state: state),
      ),
    );

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: C.bg,
            body: SafeArea(
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) {
                  final t = AppL10n.of(context);
                  return Column(children: [
                    SizedBox(
                      height: 52,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Icon(Icons.library_music_outlined, size: 17, color: C.acc),
                          const SizedBox(width: 8),
                          Text(t.sourcesTitle,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.txt)),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(t.sourcesSummary(state.localTrackCount, state.webDavTrackCount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: C.dim)),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
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
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Panel(child: _LocalBlock(state: state)),
                              const SizedBox(height: 14),
                              Panel(child: _WebDavBlock(state: state, dense: false)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),
      );
}

// ---------------- 本地 ----------------

TextStyle get _blockTitle => TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.txt);

class _LocalBlock extends StatelessWidget {
  const _LocalBlock({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final scanning = state.scanning;
    final status = scanning
        ? t.scanProgress(state.scanned, state.scanTotal)
        : state.scanError ?? (state.demoMode ? t.demoLibrary : t.libraryReady);
    final dir = state.scanDir;
    final canRescan = !state.demoMode && !scanning;
    final permission = state.permission;
    final needsPermission = permission != null && !permission.canReadLibrary;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, box) => Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(t.localSourceTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _blockTitle),
            ),
            // 1000px 附近的窄屏英文会把标题挤成「Local…」，这时省掉计数（顶部汇总里还有）。
            if (box.maxWidth >= 400) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(t.trackCount(state.localTrackCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kNums.copyWith(fontSize: 11.5, color: C.dim)),
              ),
            ],
            if (state.brokenCount > 0) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(t.missingCount(state.brokenCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kNums.copyWith(fontSize: 11, color: C.warn)),
              ),
            ],
          ]),
        ),
        _MiniBtn(
          key: const Key('local-rescan'),
          label: scanning ? t.scanning : t.rescan,
          icon: Icons.refresh_rounded,
          onTap: canRescan ? state.scanLibrary : null,
        ),
        const SizedBox(width: 6),
        _MiniBtn(
          key: const Key('local-folder'),
          label: t.changeFolder,
          icon: Icons.folder_open_rounded,
          onTap: state.demoMode ? null : () => _changeRoot(context),
        ),
      ])),
      const SizedBox(height: 6),
      Tooltip(
        message: dir.isEmpty ? (state.demoMode ? t.noRealFolder : t.noFolder) : dir,
        waitDuration: const Duration(milliseconds: 500),
        child: Text(
          dir.isEmpty ? (state.demoMode ? t.noRealFolder : t.noFolder) : dir,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: C.faint),
        ),
      ),
      const SizedBox(height: 3),
      Text(status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: state.scanError != null ? C.bad : C.dim)),
      if (scanning && state.scanTotal > 0) ...[
        const SizedBox(height: 6),
        Bar(ratio: state.scanned / state.scanTotal),
      ],
      if (needsPermission) ...[
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(permission.summary,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: C.warn)),
          ),
          _MiniBtn(label: t.grantAccess, onTap: state.requestLibraryPermission),
          const SizedBox(width: 6),
          _MiniBtn(label: t.systemSettings, onTap: state.openStorageSettings),
        ]),
      ],
    ]);
  }

  Future<void> _changeRoot(BuildContext context) async {
    final result = await showDirectoryPicker(
      context,
      initialPath: state.scanDir,
      onOpenSettings: state.openStorageSettings,
    );
    if (result == null || result == state.scanDir) return;
    await state.setLibraryRoot(result);
  }
}

// ---------------- WebDAV ----------------

class _WebDavBlock extends StatelessWidget {
  const _WebDavBlock({required this.state, required this.dense});
  final AppState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final sources = state.webDavSources;
    final header = Row(children: [
      Text(t.webdavSourceTitle, style: _blockTitle),
      const SizedBox(width: 8),
      Text(t.webdavCount(state.webDavTrackCount), style: kNums.copyWith(fontSize: 11.5, color: C.dim)),
      const Spacer(),
      // 页面模式空态已有「新增」，标题行不再重复一颗。
      if (dense || sources.isNotEmpty)
        _MiniBtn(
          key: const Key('webdav-add'),
          label: t.webdavAdd,
          icon: Icons.add_rounded,
          onTap: () => _openDialog(context),
        ),
    ]);

    if (sources.isEmpty) {
      final empty = _empty(context);
      return Column(
        mainAxisSize: dense ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          if (dense) Expanded(child: empty) else Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: empty),
        ],
      );
    }

    final rows = <Widget>[
      for (var i = 0; i < sources.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        _ServerRow(
          state: state,
          source: sources[i],
          dense: dense,
          onSync: () => _sync(sources[i].id),
          onEdit: () => _openDialog(context, editing: sources[i]),
          onDelete: () => _confirmDelete(context, sources[i]),
        ),
      ],
    ];

    return Column(
      mainAxisSize: dense ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        if (dense)
          Expanded(child: ListView(padding: EdgeInsets.zero, children: rows))
        else
          ...rows,
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final t = AppL10n.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: C.faint),
          const SizedBox(width: 8),
          Text(t.webdavEmptyTitle, style: TextStyle(fontSize: 12, color: C.dim)),
        ]),
        const SizedBox(height: 4),
        Text(t.webdavEmptyHint,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: C.faint)),
      ],
    );
    if (dense) return content;
    return Row(children: [
      const SizedBox(width: 2),
      Expanded(child: content),
      const SizedBox(width: 12),
      _MiniBtn(label: t.webdavAdd, icon: Icons.add_rounded, onTap: () => _openDialog(context)),
    ]);
  }

  Future<void> _openDialog(BuildContext context, {WebDavSource? editing}) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WebDavDialog(state: state, editing: editing),
    );
    if (id == null) return;
    await _sync(id);
  }

  Future<void> _sync(String id) async {
    if (state.webDavSyncing(id)) return;
    try {
      await state.syncWebDav(id);
    } catch (_) {
      // 失败原因已写进该音源的 lastError，由行内文案展示。
    }
  }

  Future<void> _confirmDelete(BuildContext context, WebDavSource source) async {
    final t = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel2,
        title: Text(t.webdavDeleteConfirm(source.server.displayName),
            style: TextStyle(fontSize: 13.5, color: C.txt)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel, style: TextStyle(color: C.dim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: C.bad, foregroundColor: Colors.white),
            child: Text(t.webdavDelete),
          ),
        ],
      ),
    );
    if (ok == true) await state.removeWebDav(source.id);
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.state,
    required this.source,
    required this.dense,
    required this.onSync,
    required this.onEdit,
    required this.onDelete,
  });

  final AppState state;
  final WebDavSource source;
  final bool dense;
  final VoidCallback onSync;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final syncing = state.webDavSyncing(source.id);
    final progress = state.webDavProgress(source.id);
    final error = source.lastError;
    final subtitle = syncing
        ? (progress == null ? t.webdavSyncing : t.webdavSyncProgress(progress.tracks, progress.folders))
        : '${source.server.hostLabel} · ${t.webdavCount(source.trackCount)}';
    final stampColor = error != null && !syncing ? C.warn : C.faint;
    final time = source.lastSyncAt;
    final stamp = time == null ? t.webdavNeverSynced : t.webdavSyncedAt(_stamp(time, full: !dense));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 10),
      decoration: BoxDecoration(
        color: C.panel2.withValues(alpha: .35),
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _StatusDot(color: syncing ? C.acc : error != null ? C.warn : time != null ? C.acc : C.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(source.server.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.txt)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: syncing || error != null ? stampColor : C.faint)),
            ]),
          ),
          const SizedBox(width: 8),
          if (dense) ...[
            if (!syncing)
              Tooltip(
                message: stamp,
                waitDuration: const Duration(milliseconds: 500),
                child: Text(stamp, style: TextStyle(fontSize: 10, color: stampColor)),
              ),
            const SizedBox(width: 4),
            _IconBtn(
              key: Key('webdav-sync-${source.id}'),
              icon: Icons.sync_rounded,
              tooltip: t.webdavSync,
              onTap: syncing ? null : onSync,
            ),
            _IconBtn(
              key: Key('webdav-edit-${source.id}'),
              icon: Icons.edit_outlined,
              tooltip: t.webdavEdit,
              onTap: syncing ? null : onEdit,
            ),
            _IconBtn(
              key: Key('webdav-delete-${source.id}'),
              icon: Icons.delete_outline_rounded,
              color: C.bad,
              tooltip: t.webdavDelete,
              onTap: syncing ? null : onDelete,
            ),
          ] else ...[
            Text(stamp, style: TextStyle(fontSize: 10.5, color: stampColor)),
            const SizedBox(width: 12),
            _MiniBtn(label: syncing ? t.webdavSyncing : t.webdavSync, onTap: syncing ? null : onSync),
            const SizedBox(width: 6),
            _MiniBtn(label: t.webdavEdit, onTap: syncing ? null : onEdit),
            const SizedBox(width: 6),
            _MiniBtn(label: t.webdavDelete, danger: true, onTap: syncing ? null : onDelete),
          ],
        ]),
        if (syncing) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: C.line,
              valueColor: AlwaysStoppedAnimation<Color>(C.acc),
            ),
          ),
        ],
      ]),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: color == C.acc ? [BoxShadow(color: C.acc.withValues(alpha: .55), blurRadius: 8)] : null,
        ),
      );
}

/// 紧凑时间：宽屏行内只留月日，整页管理带年份。
String _stamp(DateTime time, {bool full = false}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final date = full ? '${time.year}-${two(time.month)}-${two(time.day)}' : '${two(time.month)}-${two(time.day)}';
  return '$date $clock';
}

// ---------------- 新增/编辑弹窗 ----------------

class _WebDavDialog extends StatefulWidget {
  const _WebDavDialog({required this.state, this.editing});
  final AppState state;
  final WebDavSource? editing;

  @override
  State<_WebDavDialog> createState() => _WebDavDialogState();
}

class _WebDavDialogState extends State<_WebDavDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late bool _selfSigned;
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  bool _ok = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    final server = widget.editing?.server;
    _name = TextEditingController(text: server?.name ?? '');
    _url = TextEditingController(text: server?.url ?? '');
    _user = TextEditingController(text: server?.username ?? '');
    _pass = TextEditingController(text: server?.password ?? '');
    _selfSigned = server?.allowSelfSigned ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  WebDavServer? _build(AppL10n t) {
    final name = _name.text.trim();
    final url = WebDavServer.normalizeUrl(_url.text);
    String? error;
    if (name.isEmpty) {
      error = t.webdavNeedName;
    } else if (url.isEmpty) {
      error = t.webdavNeedUrl;
    } else if (!WebDavServer.validUrl(url)) {
      error = t.webdavInvalidUrl;
    }
    if (error != null) {
      setState(() {
        _ok = false;
        _feedback = error;
      });
      return null;
    }
    return WebDavServer(
      id: WebDavServer.idFor(url),
      name: name,
      url: url,
      username: _user.text.trim(),
      password: _pass.text,
      allowSelfSigned: _selfSigned,
      createdAt: widget.editing?.server.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _test() async {
    final t = AppL10n.of(context);
    final server = _build(t);
    if (server == null) return;
    setState(() {
      _testing = true;
      _feedback = null;
    });
    try {
      final count = await widget.state.testWebDav(server);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _feedback = t.webdavTestOk(count);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _feedback = t.webdavTestFailed('$e');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final t = AppL10n.of(context);
    final server = _build(t);
    if (server == null) return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      final source = await widget.state.saveWebDav(server, previousId: widget.editing?.id);
      if (!mounted) return;
      Navigator.of(context).pop(source.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _ok = false;
        _feedback = t.webdavTestFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final busy = _testing || _saving;
    return AlertDialog(
      backgroundColor: C.panel,
      title: Text(widget.editing == null ? t.webdavAddTitle : t.webdavEditTitle, style: kCardTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FieldLabel(t.webdavName),
            const SizedBox(height: 6),
            FormInput(key: const Key('webdav-name'), controller: _name, hint: 'NAS 音乐'),
            const SizedBox(height: 12),
            FieldLabel(t.webdavUrl),
            const SizedBox(height: 6),
            FormInput(
              key: const Key('webdav-url'),
              controller: _url,
              hint: 'https://nas.local:5006/music',
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FieldLabel(t.webdavUsername),
                  const SizedBox(height: 6),
                  FormInput(key: const Key('webdav-username'), controller: _user, hint: 'guest'),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FieldLabel(t.webdavPassword),
                  const SizedBox(height: 6),
                  FormInput(
                    key: const Key('webdav-password'),
                    controller: _pass,
                    hint: '••••••',
                    obscureText: _obscure,
                    suffix: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      color: C.faint,
                      tooltip: t.webdavPassword,
                      icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(8),
              onTap: busy ? null : () => setState(() => _selfSigned = !_selfSigned),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Checkbox(
                    key: const Key('webdav-self-signed'),
                    value: _selfSigned,
                    onChanged: busy ? null : (v) => setState(() => _selfSigned = v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t.webdavAllowSelfSigned,
                        style: TextStyle(fontSize: 12, color: C.dim)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(t.webdavDialogHint, style: kMini),
            if (_feedback != null) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    size: 14, color: _ok ? C.acc : C.bad),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_feedback!,
                      style: TextStyle(fontSize: 11.5, color: _ok ? C.acc : C.bad)),
                ),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('webdav-test'),
          onPressed: busy ? null : _test,
          child: Text(_testing ? t.webdavTesting : t.webdavTest,
              style: TextStyle(color: busy ? C.faint : C.dim)),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel, style: TextStyle(color: C.dim)),
        ),
        FilledButton(
          key: const Key('webdav-save'),
          onPressed: busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
          child: Text(_saving ? t.webdavSaving : t.webdavSaveAndScan),
        ),
      ],
    );
  }
}

// ---------------- 小件 ----------------

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({super.key, required this.label, this.icon, this.onTap, this.danger = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled ? C.line : (danger ? C.bad : C.txt);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: enabled ? C.line : C.line.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(label, style: TextStyle(fontSize: 11.5, color: fg)),
          ]),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({super.key, required this.icon, required this.tooltip, this.onTap, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        color: color ?? C.dim,
        disabledColor: C.line,
        tooltip: tooltip,
        icon: Icon(icon),
      );
}
