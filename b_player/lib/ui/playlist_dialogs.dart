import 'dart:async';

import 'package:flutter/material.dart';

import '../edge/library.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/self_playlist.dart';
import '../theme.dart';
import 'form_bits.dart';
import 'playlist_format.dart';

Future<void> showNewPlaylistDialog(BuildContext context, AppState state) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => _NewPlaylistDialog(state: state),
    );

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog({required this.state});
  final AppState state;

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final _name = TextEditingController();
  var _mode = PlaylistMode.sequential;
  var _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Dialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.createPlaylistTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.txt)),
            const SizedBox(height: 16),
            FieldLabel(t.playlistName),
            const SizedBox(height: 6),
            FormInput(
              controller: _name,
              hint: t.playlistNameHint,
              autofocus: true,
              onChanged: (_) {
                if (_error.isNotEmpty) setState(() => _error = '');
              },
              onSubmitted: (_) => _create(),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(_error, style: TextStyle(fontSize: 11, color: C.bad)),
            ],
            const SizedBox(height: 14),
            FieldLabel(t.playlistMode),
            const SizedBox(height: 7),
            Row(children: [
              Choice(
                label: t.sequential,
                on: _mode == PlaylistMode.sequential,
                onTap: () => setState(() => _mode = PlaylistMode.sequential),
              ),
              const SizedBox(width: 8),
              Choice(
                label: t.shuffle,
                on: _mode == PlaylistMode.shuffle,
                onTap: () => setState(() => _mode = PlaylistMode.shuffle),
              ),
            ]),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.cancel, style: TextStyle(color: C.dim)),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _create,
                style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
                child: Text(t.newPlaylist),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _create() {
    final t = AppL10n.of(context);
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = t.playlistNameRequired);
      return;
    }
    widget.state.createPlaylist(trimmed, _mode);
    Navigator.pop(context);
  }
}

Future<void> showPlaylistSearchDialog(
  BuildContext context,
  AppState state,
  String playlistId,
) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => _SearchDialog(state: state, playlistId: playlistId),
    );

Future<void> showPlaylistScheduleDialog(
  BuildContext context,
  AppState state,
  String playlistId,
) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => _ScheduleDialog(state: state, playlistId: playlistId),
    );

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.state, required this.playlistId});
  final AppState state;
  final String playlistId;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _filter = 'all';
  List<Track> _items = const [];
  bool _searching = false;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<({String id, String label})> _filters(AppL10n t) => [
        (id: 'all', label: t.searchAll),
        if (widget.state.library.tracks.any((x) => x.isLocal))
          (id: 'local', label: t.searchLocal),
        if (widget.state.hasWebDavTracks) (id: 'webdav', label: t.searchWebdav),
        if (widget.state.hasOnlineSearchSources) (id: 'online', label: t.searchOnline),
      ];

  void _onQuery(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _gen++;
      setState(() {
        _items = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  void _pickFilter(String id) {
    if (_filter == id) return;
    _debounce?.cancel();
    setState(() => _filter = id);
    if (_controller.text.trim().isNotEmpty) _search();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final gen = ++_gen;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final page = await widget.state.searchForPlaylist(query, filter: _filter);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = page.items;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final playlist = widget.state.playlists
        .where((p) => p.id == widget.playlistId)
        .firstOrNull;
    final filters = _filters(t);
    return Dialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(t.searchSongsTitle,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.txt)),
              ),
              if (playlist != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.panel2,
                    border: Border.all(color: C.line),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: C.dim)),
                ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, size: 18, color: C.dim),
                tooltip: t.close,
                visualDensity: VisualDensity.compact,
              ),
            ]),
            const SizedBox(height: 8),
            FormInput(
              controller: _controller,
              focusNode: _focus,
              hint: t.searchSongsHint,
              onChanged: _onQuery,
              suffix: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onQuery('');
                      },
                      icon: Icon(Icons.close_rounded, size: 15, color: C.faint),
                      tooltip: t.close,
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final f in filters)
                Choice(
                  label: f.label,
                  on: _filter == f.id,
                  compact: true,
                  onTap: () => _pickFilter(f.id),
                ),
            ]),
            const SizedBox(height: 10),
            Divider(height: 1, color: C.line),
            Expanded(child: _body(t)),
            Divider(height: 1, color: C.line),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  playlist == null ? '' : t.playlistCount(playlist.tracks.length),
                  style: kMini,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: C.dim),
                child: Text(t.done),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _body(AppL10n t) {
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(t.searchStartHint, style: TextStyle(fontSize: 12, color: C.faint)),
      );
    }
    if (_searching) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_failed) {
      return Center(child: Text(t.searchFailed, style: TextStyle(fontSize: 12, color: C.warn)));
    }
    if (_items.isEmpty) {
      return Center(child: Text(t.searchNoResult, style: TextStyle(fontSize: 12, color: C.faint)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _items.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: C.line),
      itemBuilder: (context, i) => _ResultRow(
        state: widget.state,
        playlistId: widget.playlistId,
        track: _items[i],
        onChanged: () => setState(() {}),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.state,
    required this.playlistId,
    required this.track,
    required this.onChanged,
  });
  final AppState state;
  final String playlistId;
  final Track track;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final inList = state.isInPlaylist(track.trackKey, playlistId: playlistId);
    final tags = state.sourceTags(track.trackKey);
    final detail = [
      if (track.artist.trim().isNotEmpty) track.artist,
      if (track.durationMs > 0) fmtMs(track.durationMs),
      ...tags,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.music_note_rounded, size: 16, color: C.faint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: C.txt)),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: C.faint)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: Align(
            alignment: Alignment.centerRight,
            child: inList
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded, size: 14, color: C.acc),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(t.alreadyInPlaylist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: C.acc)),
                    ),
                  ])
                : TextButton(
                    onPressed: () {
                      state.addToPlaylist(track.trackKey, playlistId: playlistId);
                      onChanged();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: C.acc,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 30),
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: Text(t.addToPlaylist),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.state, required this.playlistId});
  final AppState state;
  final String playlistId;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late bool _enabled;
  late Set<int> _days;
  late List<PlaylistWindow> _windows;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final source = widget.state.playlists
        .where((p) => p.id == widget.playlistId)
        .firstOrNull;
    final schedule = source?.schedule ?? PlaylistSchedule();
    _enabled = schedule.enabled;
    _days = {...schedule.days};
    _windows = [for (final w in schedule.windows) w.copyWith()];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final playlist = widget.state.playlists
        .where((p) => p.id == widget.playlistId)
        .firstOrNull;
    return Dialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(t.scheduleTitle,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.txt)),
              ),
              if (playlist != null)
                Flexible(
                  child: Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: C.faint)),
                ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, size: 18, color: C.dim),
                tooltip: t.close,
                visualDensity: VisualDensity.compact,
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(t.scheduleEnable, style: TextStyle(fontSize: 12.5, color: C.txt)),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ]),
            const SizedBox(height: 8),
            FieldLabel(t.scheduleDays),
            const SizedBox(height: 7),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var day = 1; day <= 7; day++)
                Choice(
                  label: weekdayShort(t, day),
                  on: _days.contains(day),
                  compact: true,
                  fill: C.panel2,
                  onTap: () => setState(() {
                    if (!_days.remove(day)) _days.add(day);
                    _error = '';
                  }),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: FieldLabel(t.scheduleRanges)),
              TextButton.icon(
                onPressed: () => setState(() {
                  _windows.add(const PlaylistWindow(9 * 60, 12 * 60));
                  _error = '';
                }),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: Text(t.scheduleAddRange),
                style: TextButton.styleFrom(
                  foregroundColor: C.dim,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  for (var i = 0; i < _windows.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _RangeRow(
                        window: _windows[i],
                        canDelete: _windows.length > 1,
                        onChanged: (w) => setState(() {
                          _windows[i] = w;
                          _error = '';
                        }),
                        onDelete: () => setState(() {
                          _windows.removeAt(i);
                          _error = '';
                        }),
                      ),
                    ),
                ]),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_error, style: TextStyle(fontSize: 11, color: C.bad)),
            ],
            const SizedBox(height: 6),
            Text(t.scheduleHint, style: TextStyle(fontSize: 10.5, color: C.faint)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.cancel, style: TextStyle(color: C.dim)),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
                child: Text(t.done),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _save() {
    final t = AppL10n.of(context);
    if (_enabled) {
      if (_days.isEmpty) {
        setState(() => _error = t.scheduleNeedDays);
        return;
      }
      if (_windows.isEmpty) {
        setState(() => _error = t.scheduleNeedRange);
        return;
      }
      if (_windows.any((w) => w.startMinutes == w.endMinutes)) {
        setState(() => _error = t.scheduleRangeInvalid);
        return;
      }
    }
    widget.state.updatePlaylistSchedule(
      widget.playlistId,
      PlaylistSchedule(enabled: _enabled, days: _days, windows: _windows),
    );
    Navigator.pop(context);
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.window,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });
  final PlaylistWindow window;
  final bool canDelete;
  final ValueChanged<PlaylistWindow> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: _TimeButton(
            minutes: window.startMinutes,
            onPicked: (m) => onChanged(window.copyWith(startMinutes: m)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Text('–', style: TextStyle(fontSize: 12, color: C.faint)),
        ),
        Expanded(
          child: _TimeButton(
            minutes: window.endMinutes,
            onPicked: (m) => onChanged(window.copyWith(endMinutes: m)),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: canDelete ? onDelete : null,
          icon: Icon(Icons.remove_circle_outline_rounded, size: 16, color: canDelete ? C.faint : C.line),
          visualDensity: VisualDensity.compact,
          splashRadius: 16,
        ),
      ]);
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.minutes, required this.onPicked});
  final int minutes;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.panel2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          );
          if (picked != null) onPicked(picked.hour * 60 + picked.minute);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.schedule_rounded, size: 14, color: C.faint),
            const SizedBox(width: 6),
            Text(fmtMinutes(minutes),
                style: kNums.copyWith(fontSize: 12.5, color: C.txt)),
          ]),
        ),
      ),
    );
  }
}
