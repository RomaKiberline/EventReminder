/// Domain objects, independent of Flutter widgets and SQLite.
DateTime fromDbDate(String value) => DateTime.parse(value).toLocal();
String toDbDate(DateTime value) => value.toUtc().toIso8601String();
DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime dayEnd(DateTime date) => dayStart(date).add(const Duration(days: 1));
bool sameDay(DateTime x, DateTime y) => x.year == y.year && x.month == y.month && x.day == y.day;

class Category {
  final int id;
  final String name;
  final String colorHex;
  const Category(this.id, this.name, this.colorHex);
}

class RecurrenceRule {
  final int? id;
  final String frequency; // DAILY, WEEKLY, MONTHLY
  final int interval;
  final DateTime? until;
  final int? count;
  final List<int> weekdays; // Monday=1 ... Sunday=7
  const RecurrenceRule({this.id, required this.frequency, this.interval = 1,
    this.until, this.count, this.weekdays = const []});
}

class EventItem {
  final int? id;
  final String title;
  final String description;
  final String location;
  final DateTime start;
  final DateTime? end;
  final String status;
  final int? categoryId;
  final RecurrenceRule? recurrence;
  final List<int> reminderOffsets;
  const EventItem({this.id, required this.title, this.description = '',
    this.location = '', required this.start, this.end, this.status = 'PLANNED',
    this.categoryId, this.recurrence, this.reminderOffsets = const []});
  bool get valid => title.trim().isNotEmpty && (end == null || !end!.isBefore(start));
}

class EventException {
  final int eventId;
  final DateTime originalStart;
  final String type;
  final DateTime? overrideStart;
  final DateTime? overrideEnd;
  final String? overrideTitle;
  const EventException({required this.eventId, required this.originalStart,
    required this.type, this.overrideStart, this.overrideEnd, this.overrideTitle});
}

class EventOccurrence {
  final EventItem event;
  final DateTime originalStart;
  final DateTime start;
  final DateTime? end;
  final String title;
  final String status;
  const EventOccurrence({required this.event, required this.originalStart,
    required this.start, this.end, required this.title, required this.status});
  String get identity => '${event.id}:${toDbDate(originalStart)}';
}

class AppSnapshot {
  final List<EventItem> events;
  final List<Category> categories;
  final List<EventException> exceptions;
  final Map<String,String> settings;
  const AppSnapshot({required this.events, required this.categories,
    required this.exceptions, required this.settings});
}
