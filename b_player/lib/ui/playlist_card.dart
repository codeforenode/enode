import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/self_playlist.dart';
import '../theme.dart';
import 'cards.dart';
import 'form_bits.dart';
import 'playlist_dialogs.dart';
import 'playlist_format.dart';

/// 播放列表卡：点歌插播区始终在最上，自建列表在下面，互不混排。
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final hasLists = state.playlists.isNotEmpty;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardHead(t.queue, trailing: t.queueLimit(state.queue.length)),
        Expanded(
          flex: hasLists ? 2 : 1,
          child: _RequestSection(state: state),
        ),
        if (hasLists)
          Expanded(flex: 3, child: _LocalSection(state: state))
        else
          _NoLists(state: state),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.icon, this.accent = false});
  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: accent ? C.acc : C.faint),
          const SizedBox(width: 5),
        ],
        Text(text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
              color: accent ? C.acc : C.faint,
            )),
      ]);
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip();

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: C.acc.withValues(alpha: .12),
        border: Border.all(color: C.acc.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(t.priorityTag, style: TextStyle(fontSize: 9.5, color: C.acc)),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _SectionTitle(text: t.requestQueue, icon: Icons.bolt_rounded, accent: true),
        const SizedBox(width: 6),
        const _PriorityChip(),
      ]),
      const SizedBox(height: 4),
      Expanded(
        child: state.queue.isEmpty
            ? Center(child: Text(t.noRequests, style: kMini))
            : ReorderableListView.builder(
                padding: EdgeInsets.zero,
                buildDefaultDragHandles: false,
                itemCount: state.queue.length,
                onReorderItem: (from, to) => _confirmMove(context, from, to),
                itemBuilder: (context, i) {
                  final item = state.queue[i];
                  return ReorderableDelayedDragStartListener(
                    key: ObjectKey(item),
                    index: i,
                    child: _QueueRow(
                      index: i,
                      item: item,
                      head: i == 0,
                      playing: i == 0 && state.playing,
                      onDelete: () => state.removeAt(i),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _confirmMove(BuildContext context, int from, int to) async {
    if (from == to) return;
    final item = state.queue[from];
    final t = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(text: t.moveToPosition(item.title, to + 1)),
    );
    if (ok == true) state.move(from, to);
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    required this.item,
    required this.head,
    required this.playing,
    this.onDelete,
  });
  final int index;
  final QueueItem item;
  final bool head;
  final bool playing;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
        gradient: index == 0
            ? LinearGradient(colors: [C.acc.withValues(alpha: .07), Colors.transparent])
            : null,
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          child: Text('${index + 1}',
              textAlign: TextAlign.right, style: kNums.copyWith(fontSize: 11, color: C.faint)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: C.txt)),
            const SizedBox(height: 1),
            Row(children: [
              Flexible(
                child: Text(
                  item.durationMs > 0 ? '${item.artist} · ${fmtMs(item.durationMs)}' : item.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: C.faint),
                ),
              ),
              if (item.seat != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: C.panel2,
                    border: Border.all(color: C.line),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(item.seat!, style: TextStyle(fontSize: 10, color: C.dim)),
                ),
              ],
            ]),
          ]),
        ),
        if (head)
          Text(playing ? t.playingNow : t.paused,
              style: TextStyle(fontSize: 10.5, color: playing ? C.acc : C.dim))
        else
          IconButton(
            onPressed: onDelete,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            splashRadius: 15,
            color: C.faint,
            icon: const Icon(Icons.close_rounded),
            tooltip: t.removeFromQueue,
          ),
      ]),
    );
  }
}

class _NoLists extends StatelessWidget {
  const _NoLists({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: C.panel2,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.queue_music_rounded, size: 17, color: C.faint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.playlistNoLists, style: TextStyle(fontSize: 12.5, color: C.txt)),
            const SizedBox(height: 2),
            Text(t.playlistNoListsHint,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: C.faint)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => unawaited(showNewPlaylistDialog(context, state)),
          style: FilledButton.styleFrom(
            backgroundColor: C.acc,
            foregroundColor: C.onAcc,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(t.newPlaylist, style: const TextStyle(fontSize: 11.5)),
        ),
      ]),
    );
  }
}

class _LocalSection extends StatelessWidget {
  const _LocalSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final playlist = state.activePlaylist;
    if (playlist == null) return const SizedBox.shrink();
    final waiting = state.queue.isNotEmpty;
    final localPlaying = !waiting && state.localOutputActive && state.playing;
    final schedule = playlistScheduleLabel(playlist.schedule);
    final inWindow = playlist.schedule.enabled &&
        playlist.schedule.canRun &&
        state.activePlaylistInWindow;
    return Container(
      padding: const EdgeInsets.only(top: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _SectionTitle(text: t.selfPlaylists, icon: Icons.queue_music_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: playlist.id,
                isDense: true,
                isExpanded: true,
                dropdownColor: C.panel2,
                borderRadius: BorderRadius.circular(9),
                icon: Icon(Icons.expand_more_rounded, size: 17, color: C.faint),
                style: TextStyle(fontSize: 12.5, color: C.txt),
                selectedItemBuilder: (context) => [
                  for (final p in state.playlists)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(p.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: C.txt)),
                    ),
                ],
                items: [
                  for (final p in state.playlists)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: C.txt)),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) state.selectPlaylist(id);
                },
              ),
            ),
          ),
          _IconBtn(
            icon: Icons.add_rounded,
            tooltip: t.newPlaylist,
            onTap: () => unawaited(showNewPlaylistDialog(context, state)),
          ),
          _IconBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: t.deletePlaylist,
            onTap: () => _confirmDelete(context, playlist),
          ),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Choice(
            label: t.sequential,
            on: playlist.mode == PlaylistMode.sequential,
            compact: true,
            onTap: () => state.setPlaylistMode(playlist.id, PlaylistMode.sequential),
          ),
          Choice(
            label: t.shuffle,
            on: playlist.mode == PlaylistMode.shuffle,
            compact: true,
            onTap: () => state.setPlaylistMode(playlist.id, PlaylistMode.shuffle),
          ),
          _ScheduleChip(
            label: playlist.schedule.enabled
                ? (inWindow ? t.scheduleActiveNow : (schedule.isEmpty ? t.schedule : schedule))
                : t.scheduleOff,
            active: inWindow,
            onTap: () => unawaited(showPlaylistScheduleDialog(context, state, playlist.id)),
          ),
          Tooltip(
            message: state.canSearchSongs ? t.searchAdd : t.playlistSearchUnavailable,
            child: TextButton.icon(
              onPressed: state.canSearchSongs
                  ? () => unawaited(showPlaylistSearchDialog(context, state, playlist.id))
                  : null,
              icon: const Icon(Icons.search_rounded, size: 15),
              label: Text(t.searchAdd),
              style: TextButton.styleFrom(
                foregroundColor: C.dim,
                disabledForegroundColor: C.faint,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                textStyle: const TextStyle(fontSize: 11.5),
              ),
            ),
          ),
          _IconBtn(
            icon: localPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: waiting
                ? t.playlistWaitingRequests
                : (localPlaying ? t.pausePlaylist : t.playPlaylist),
            onTap: waiting || playlist.tracks.isEmpty
                ? null
                : state.toggleLocalPlayback,
            accent: localPlaying,
          ),
        ]),
        if (state.localInterrupted) ...[
          const SizedBox(height: 6),
          _InterruptBanner(time: fmtMs(state.localSavedPosition)),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: playlist.tracks.isEmpty
              ? Center(
                  child: Text(t.playlistEmptyHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: C.faint)),
                )
              : ReorderableListView.builder(
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
                  itemCount: playlist.tracks.length,
                  onReorderItem: (from, to) =>
                      state.movePlaylistTrack(from, to, playlistId: playlist.id),
                  itemBuilder: (context, i) {
                    final entry = playlist.tracks[i];
                    final current = !waiting && state.localOutputActive && i == playlist.index;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('local-${playlist.id}-${entry.trackKey}'),
                      index: i,
                      child: _LocalRow(
                        index: i,
                        entry: entry,
                        current: current,
                        playing: current && state.playing,
                        onDelete: () => state.removePlaylistTrack(i, playlistId: playlist.id),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SelfPlaylist playlist) async {
    final t = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(text: t.deletePlaylistConfirm(playlist.name), danger: true),
    );
    if (ok == true) state.deletePlaylist(playlist.id);
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Tooltip(
      message: t.schedule,
      child: Material(
        color: active ? C.acc.withValues(alpha: .14) : C.panel2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: active ? C.acc : C.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.schedule_rounded, size: 13, color: active ? C.acc : C.dim),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? C.acc : C.dim,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InterruptBanner extends StatelessWidget {
  const _InterruptBanner({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Tooltip(
      message: t.playlistResumeHint(time),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: C.acc.withValues(alpha: .08),
          border: Border.all(color: C.acc.withValues(alpha: .28)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.swap_horiz_rounded, size: 14, color: C.acc),
          const SizedBox(width: 6),
          Expanded(
            child: Text(t.playlistInterrupted(time),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: C.acc)),
          ),
        ]),
      ),
    );
  }
}

class _LocalRow extends StatelessWidget {
  const _LocalRow({
    required this.index,
    required this.entry,
    required this.current,
    required this.playing,
    required this.onDelete,
  });
  final int index;
  final PlaylistEntry entry;
  final bool current;
  final bool playing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
        gradient: current
            ? LinearGradient(colors: [C.acc.withValues(alpha: .07), Colors.transparent])
            : null,
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          child: current
              ? Icon(playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                  size: 12, color: C.acc)
              : Text('${index + 1}',
                  textAlign: TextAlign.right,
                  style: kNums.copyWith(fontSize: 10.5, color: C.faint)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: current ? C.acc : C.txt)),
            const SizedBox(height: 1),
            Text(
              entry.durationMs > 0
                  ? '${entry.artist} · ${fmtMs(entry.durationMs)}'
                  : entry.artist,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: C.faint),
            ),
          ]),
        ),
        IconButton(
          onPressed: onDelete,
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          splashRadius: 15,
          color: C.faint,
          icon: const Icon(Icons.close_rounded),
          tooltip: t.removeFromPlaylist,
        ),
      ]),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.accent = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        iconSize: 17,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
        color: accent ? C.acc : C.dim,
        disabledColor: C.faint,
      );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.text, this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Dialog(
      backgroundColor: C.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(fontSize: 13.5, color: C.txt)),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel, style: TextStyle(color: C.dim)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: danger ? C.bad : C.acc,
                foregroundColor: danger ? Colors.white : C.onAcc,
              ),
              child: Text(danger ? t.delete : t.confirm),
            ),
          ]),
        ]),
      ),
    );
  }
}
