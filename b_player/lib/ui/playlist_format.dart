import '../l10n/l10n.dart';
import '../state/self_playlist.dart';

String fmtMinutes(int minutes) {
  final m = minutes.clamp(0, 1439);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String playlistWindowLabel(PlaylistWindow window) =>
    '${fmtMinutes(window.startMinutes)}–${fmtMinutes(window.endMinutes)}';

String playlistScheduleLabel(PlaylistSchedule schedule) {
  if (!schedule.enabled || schedule.windows.isEmpty) return '';
  final first = playlistWindowLabel(schedule.windows.first);
  final more = schedule.windows.length - 1;
  return more > 0 ? '$first +$more' : first;
}

String weekdayShort(AppL10n t, int day) => switch (day) {
      1 => t.weekdayMon,
      2 => t.weekdayTue,
      3 => t.weekdayWed,
      4 => t.weekdayThu,
      5 => t.weekdayFri,
      6 => t.weekdaySat,
      _ => t.weekdaySun,
    };
