import 'models.dart';

/// Expands local calendar dates; daily/weekly repetitions stay at the same wall time.
/// Only a requested range is returned. Cancelled and modified occurrences are applied.
List<EventOccurrence> expandOccurrences(
  EventItem event, List<EventException> exceptions, DateTime from, DateTime until,
) {
  if (!until.isAfter(from)) return [];
  final starts = <DateTime>[];
  final rule = event.recurrence;
  if (rule == null) {
    starts.add(event.start);
  } else {
    final base = event.start;
    final last = until.add(const Duration(days: 366));
    final untilBoundary = rule.until == null ? last : dayEnd(rule.until!);
    final maxDate = untilBoundary.isBefore(last) ? untilBoundary : last;
    var generated = 0;
    if (rule.frequency == 'MONTHLY') {
      for (var n = 0; n < 2400 && generated < 10000; n++) {
        final monthIndex = base.year * 12 + base.month - 1 + n * rule.interval;
        final yr = monthIndex ~/ 12;
        final mo = monthIndex % 12 + 1;
        final candidate = DateTime(yr, mo, base.day, base.hour, base.minute);
        // A date such as 31 February does not exist; skip it instead of rolling.
        if (candidate.month != mo) continue;
        if (candidate.isAfter(maxDate)) break;
        if (candidate.isBefore(base)) continue;
        generated++;
        if (rule.count != null && generated > rule.count!) break;
        starts.add(candidate);
      }
    } else {
      final baseDay = dayStart(base);
      for (var n = 0; n < 36600 && generated < 10000; n++) {
        final date = DateTime(base.year, base.month, base.day + n, base.hour, base.minute);
        if (date.isAfter(maxDate)) break;
        if (date.isBefore(base)) continue;
        bool include;
        if (rule.frequency == 'DAILY') {
          include = n % rule.interval == 0;
        } else {
          final firstMonday = dayStart(baseDay.subtract(Duration(days: base.weekday - 1)));
          final thisMonday = dayStart(date.subtract(Duration(days: date.weekday - 1)));
          final weekIndex = DateTime.utc(thisMonday.year,thisMonday.month,thisMonday.day)
            .difference(DateTime.utc(firstMonday.year,firstMonday.month,firstMonday.day)).inDays ~/ 7;
          final validDays = rule.weekdays.isEmpty ? [base.weekday] : rule.weekdays;
          include = weekIndex % rule.interval == 0 && validDays.contains(date.weekday);
        }
        if (!include) continue;
        generated++;
        if (rule.count != null && generated > rule.count!) break;
        starts.add(date);
      }
    }
  }
  final byOriginal = <String,EventException>{
    for (final ex in exceptions.where((x) => x.eventId == event.id))
      toDbDate(ex.originalStart): ex,
  };
  final result = <EventOccurrence>[];
  final used = <String>{};
  void add(DateTime original) {
    final key = toDbDate(original);
    if (!used.add(key)) return;
    final ex = byOriginal[key];
    if (ex?.type == 'CANCELLED') return;
    final changed = ex?.type == 'MODIFIED';
    final start = changed ? ex!.overrideStart ?? original : original;
    final duration = event.end?.difference(event.start);
    final end = changed && ex!.overrideEnd != null
      ? ex.overrideEnd : (duration == null ? null : start.add(duration));
    if (start.isBefore(from) || !start.isBefore(until)) return;
    result.add(EventOccurrence(event: event, originalStart: original, start: start,
      end: end, title: changed ? (ex?.overrideTitle ?? event.title) : event.title,
      status: ex != null && ['DONE','MISSED'].contains(ex.type) ? ex.type : event.status));
  }
  for (final original in starts) { add(original); }
  // Also include rescheduled exceptions whose original date lies outside the view.
  for (final ex in byOriginal.values) {
    if (ex.type == 'MODIFIED' && ex.overrideStart != null &&
        !ex.overrideStart!.isBefore(from) && ex.overrideStart!.isBefore(until)) {
      add(ex.originalStart);
    }
  }
  result.sort((a,b) => a.start.compareTo(b.start));
  return result;
}
