import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: C.panel,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class CardHead extends StatelessWidget {
  const CardHead(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(title, style: kCardTitle),
          const Spacer(),
          if (trailing != null) Flexible(child: Text(trailing!, style: kMini, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class Dot extends StatelessWidget {
  const Dot({super.key, this.on = false});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: on ? C.acc : C.faint,
          shape: BoxShape.circle,
          boxShadow: on ? [BoxShadow(color: C.acc.withValues(alpha: .55), blurRadius: 8)] : null,
        ),
      );
}

class Bar extends StatelessWidget {
  const Bar({
    super.key,
    required this.ratio,
    this.color,
    this.height = 6,
    this.showThumb = false,
  });
  final double ratio;
  final Color? color;
  final double height;
  final bool showThumb;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? C.acc;
    final radius = BorderRadius.circular(height);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 0.0;
      final done = w * ratio.clamp(0.0, 1.0);
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: C.faint.withValues(alpha: .45),
                borderRadius: radius,
              ),
            ),
          ),
          if (done > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: done,
              child: DecoratedBox(decoration: BoxDecoration(color: fill, borderRadius: radius)),
            ),
          if (showThumb && w > height * 2)
            Positioned(
              left: (done - height).clamp(0.0, w - height * 2),
              top: -height / 2,
              child: Container(
                width: height * 2,
                height: height * 2,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: fill.withValues(alpha: .5), blurRadius: 6)],
                ),
              ),
            ),
        ]),
      );
    });
  }
}

// ---------------- 播放 ----------------

class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key, required this.state, this.compact = false});
  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final np = state.nowPlaying;
    final t = AppL10n.of(context);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardHead(t.nowPlaying,
            trailing: np == null ? t.queueEmpty : t.queuePosition(state.queue.length)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverArt(uri: state.coverUri, size: compact ? 84 : 132),
          SizedBox(width: compact ? 12 : 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(np?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: compact ? 17 : 21, fontWeight: FontWeight.w700, color: C.txt)),
              const SizedBox(height: 3),
              Text(np?.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: C.dim)),
              if (np != null) ...[
                const SizedBox(height: 7),
                _TagRow(tags: [
                  // 只有真的带了桌号才显示来源；缺失时整块不出现。
                  if (np.seat != null) t.fromGuest(np.seat!),
                  ...state.sourceTags(np.trackKey),
                ]),
              ],
              LyricBlock(state: state, compact: compact),
              const SizedBox(height: 6),
              _SeekBar(state: state),
              const SizedBox(height: 2),
              _TimeRow(state: state),
              const SizedBox(height: 8),
              _Controls(state: state, compact: compact),
              if (state.playbackError != null) ...[
                const SizedBox(height: 10),
                _ErrorBanner(text: state.playbackError!),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// 封面：本地曲目用同目录图片，在线曲目用平台返回的地址；取不到就留音符占位。
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, this.uri, this.size = 120});
  final Uri? uri;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size > 100 ? 12 : 10),
          border: Border.all(color: C.line),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.panel2, C.panel],
          ),
        ),
        child: _art(),
      );

  Widget _art() {
    final u = uri;
    if (u == null) return _placeholder();
    if (u.scheme == 'file') {
      return Image.file(File(u.toFilePath()), fit: BoxFit.cover, errorBuilder: _failed);
    }
    return Image.network(u.toString(), fit: BoxFit.cover, errorBuilder: _failed);
  }

  static Widget _failed(BuildContext _, Object _, StackTrace? _) => _placeholder();

  static Widget _placeholder() => Center(
        child: Icon(Icons.music_note_rounded, size: 26, color: C.faint),
      );
}

/// 当前歌词行（带上一句）；没有歌词时整块不占位。
class LyricBlock extends StatelessWidget {
  const LyricBlock({super.key, required this.state, this.compact = false});
  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lines = state.lyricLines;
    if (lines.isEmpty) return const SizedBox.shrink();
    final index = state.lyricIndex;
    final current = index < 0 ? lines.first.text : lines[index].text;
    final previous = index > 0 ? lines[index - 1].text : null;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (previous != null) ...[
          Text(previous,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: C.faint)),
          const SizedBox(height: 3),
        ],
        Text(current,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13.5 : 15.5,
              fontWeight: FontWeight.w600,
              color: index < 0 ? C.dim : C.txt,
            )),
      ]),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: C.panel2,
              border: Border.all(color: C.line),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(t, style: TextStyle(fontSize: 10.5, color: C.dim)),
          ),
      ]);
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final np = state.nowPlaying;
    final position = np?.positionMs ?? 0;
    final duration = np?.durationMs ?? 0;
    final remaining = duration > 0 ? (duration - position).clamp(0, duration) : 0;
    return Row(children: [
      Text(fmtMs(position), style: kNums.copyWith(fontSize: 11.5, color: C.faint)),
      const Spacer(),
      Text(duration > 0 ? t.timeLeft(fmtMs(remaining)) : '—',
          style: kNums.copyWith(fontSize: 11.5, color: C.dim)),
    ]);
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.compact});
  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    final transport = (compact ? 148.0 : 162.0);
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
      // 播放卡在半宽窗口里只有 ~240px，音量组按余量逐级降级，避免挤出卡片。
      final room = c.maxWidth - transport * scale;
      final barW = room >= 108 * scale ? (compact ? 56.0 : 78.0) : (room >= 44 * scale ? 44.0 : 0.0);
      final showNumber = barW > 0 && room >= (barW + 30) * scale;
      final showLabel = !compact && barW >= 78 && room >= (barW + 61) * scale;
      return Row(children: [
        _RoundBtn(icon: Icons.skip_previous_rounded, onTap: state.previous, size: compact ? 38 : 42),
        const SizedBox(width: 8),
        _RoundBtn(
          icon: state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: state.togglePlay,
          size: compact ? 46 : 52,
          primary: true,
        ),
        const SizedBox(width: 8),
        _RoundBtn(icon: Icons.skip_next_rounded, onTap: state.skip, size: compact ? 38 : 42),
        const SizedBox(width: 10),
        const Spacer(),
        if (showLabel) ...[
          Text(t.volume, style: TextStyle(fontSize: 11, color: C.faint)),
          const SizedBox(width: 7),
        ],
        if (barW > 0) ...[
          _VolumeBar(state: state, width: barW),
          if (showNumber) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 24,
              child: Text('${(state.volume * 100).round()}',
                  style: kNums.copyWith(fontSize: 11.5, color: C.dim)),
            ),
          ],
        ],
      ]);
    });
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: C.warn.withValues(alpha: .10),
          border: Border.all(color: C.warn.withValues(alpha: .40)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, size: 15, color: C.warn),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: C.warn)),
          ),
        ]),
      );
}

/// 进度条：点按或左右拖动直接 seek。
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final np = state.nowPlaying;
    final ratio = np == null || np.durationMs <= 0 ? 0.0 : np.positionMs / np.durationMs;
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seek(d.localPosition.dx, c.maxWidth),
        onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx, c.maxWidth),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(height: 30, child: Center(child: Bar(ratio: ratio, showThumb: true, height: 7))),
        ),
      ),
    );
  }

  void _seek(double dx, double width) {
    final np = state.nowPlaying;
    if (np == null || width <= 0 || np.durationMs <= 0) return;
    state.seekTo((dx / width * np.durationMs).round());
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.state, required this.width});
  final AppState state;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 18,
        child: LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _set(d.localPosition.dx, c.maxWidth),
            onHorizontalDragUpdate: (d) => _set(d.localPosition.dx, c.maxWidth),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Center(child: Bar(ratio: state.volume, color: C.dim, height: 6, showThumb: true)),
            ),
          ),
        ),
      );

  void _set(double dx, double width) {
    if (width <= 0) return;
    state.setVolume(dx / width);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.size = 40, this.primary = false});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? Colors.transparent : C.panel2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: primary ? null : Border.all(color: C.line),
              gradient: primary
                  ? LinearGradient(colors: [C.acc, C.acc2], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              boxShadow: primary ? [BoxShadow(color: C.acc.withValues(alpha: .28), blurRadius: 20, offset: const Offset(0, 6))] : null,
            ),
            child: Icon(icon, size: primary ? 24 : 20, color: primary ? C.onAcc : C.txt),
          ),
        ),
      );
}

// ---------------- 队列 ----------------

class QueueCard extends StatelessWidget {
  const QueueCard({super.key, required this.state, this.compact = false});
  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardHead(t.queue, trailing: t.queueLimit(state.queue.length)),
          if (state.queue.isEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(child: Text(t.queueEmpty, style: kMini)),
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.zero,
                buildDefaultDragHandles: false,
                itemCount: state.queue.length,
                onReorderItem: (from, to) => _confirmMove(context, from, to),
                itemBuilder: (context, i) {
                  final it = state.queue[i];
                  return ReorderableDelayedDragStartListener(
                    key: ObjectKey(it),
                    index: i,
                    child: _QueueRow(
                      index: i,
                      item: it,
                      head: i == 0,
                      playing: i == 0 && state.playing,
                      onDelete: () => state.removeAt(i),
                    ),
                  );
                },
              ),
            ),
        ]),
      );
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
  const _QueueRow({required this.index, required this.item, required this.head, required this.playing, this.onDelete});
  final int index;
  final QueueItem item;
  final bool head;
  final bool playing;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppL10n.of(context);
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: C.line)),
          gradient: index == 0
              ? LinearGradient(colors: [C.acc.withValues(alpha: .07), Colors.transparent])
              : null,
        ),
        child: Row(children: [
          SizedBox(
            width: 22,
            child: Text('${index + 1}', textAlign: TextAlign.right, style: kNums.copyWith(fontSize: 11, color: C.faint)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: C.txt)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                      item.durationMs > 0 ? '${item.artist} · ${fmtMs(item.durationMs)}' : item.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: C.faint)),
                ),
                const SizedBox(width: 6),
                // 没带桌号的曲目（多为对接方漏传 seat）什么都不显示：
                // 挂个「本机」标签等于把缺失当成一种身份，反而误导。
                if (item.seat != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: C.panel2,
                      border: Border.all(color: C.line),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(item.seat!, style: TextStyle(fontSize: 10.5, color: C.dim)),
                  ),
              ]),
            ]),
          ),
          if (head)
            Text(playing ? t.playingNow : t.paused,
                style: TextStyle(fontSize: 11, color: playing ? C.acc : C.dim))
          else
            IconButton(
              onPressed: onDelete,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              splashRadius: 16,
              color: C.faint,
              icon: const Icon(Icons.close_rounded),
              tooltip: t.removeFromQueue,
            ),
        ]),
      );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.text});
  final String text;

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
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: Text(t.cancel, style: TextStyle(color: C.dim))),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: C.acc, foregroundColor: C.onAcc),
                child: Text(t.confirm),
              ),
            ]),
          ]),
        ),
      );
  }
}
