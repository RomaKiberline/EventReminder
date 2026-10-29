import 'dart:convert';
import '../domain/models.dart';
import '../domain/repository.dart';
import 'api_client.dart';

/// Remote implementation of the SAME interface used by the offline SQLite UI.
/// Only activated when EVENT_REMINDER_API_URL is supplied at startup.
class ApiEventRepository implements IEventRepository {
  ApiEventRepository(this.api);
  final ApiClient api;

  Map<String, dynamic> _map(dynamic raw) => Map<String, dynamic>.from(raw as Map);

  RecurrenceRule? _recurrence(dynamic raw) {
    if (raw == null) return null;
    final r = _map(raw);
    return RecurrenceRule(
      id: r['id'] as int?, frequency: r['frequency'] as String,
      interval: r['interval_value'] as int,
      until: r['until_date'] == null ? null : fromDbDate(r['until_date'] as String),
      count: r['occurrence_count'] as int?,
      weekdays: List<int>.from(r['weekdays'] as List? ?? const []),
    );
  }

  EventItem _event(dynamic raw) {
    final e = _map(raw);
    return EventItem(
      id: e['id'] as int, title: e['title'] as String,
      description: e['description'] as String? ?? '',
      location: e['location'] as String? ?? '',
      start: fromDbDate(e['start_at'] as String),
      end: e['end_at'] == null ? null : fromDbDate(e['end_at'] as String),
      status: e['status'] as String, categoryId: e['category_id'] as int?,
      recurrence: _recurrence(e['recurrence']),
      reminderOffsets: [for (final r in e['reminders'] as List? ?? const [])
        if (_map(r)['is_enabled'] != 0) _map(r)['offset_minutes'] as int],
    );
  }

  Map<String, dynamic> _writeEvent(EventItem e) => {
    'title': e.title.trim(), 'description': e.description,
    'location': e.location, 'start_at': toDbDate(e.start),
    'end_at': e.end == null ? null : toDbDate(e.end!),
    'status': e.status, 'category_id': e.categoryId,
    'reminder_offsets': e.reminderOffsets.toSet().toList(),
    'recurrence': e.recurrence == null ? null : {
      'frequency': e.recurrence!.frequency,
      'interval_value': e.recurrence!.interval,
      // `until_date` is a datetime (not a plain date) in the API contract.
      'until_date': e.recurrence!.until == null ? null : toDbDate(e.recurrence!.until!),
      'occurrence_count': e.recurrence!.count,
      'weekdays': e.recurrence!.weekdays,
    },
  };

  @override
  Future<AppSnapshot> loadAll() async {
    final categories = (await api.request('GET', '/api/categories') as List)
      .map((raw) {final c=_map(raw);return Category(c['id'] as int,
        c['name'] as String,c['color_hex'] as String);}).toList();
    final events = <EventItem>[];
    final exceptions = <EventException>[];
    // API has pagination. Fetch all pages, not only the first 100 events.
    for (var offset=0;;offset+=500) {
      final page=await api.request('GET', '/api/events?limit=500&offset=$offset') as List;
      for (final raw in page) {
        final e=_map(raw);
        events.add(_event(e));
        for (final rawEx in e['exceptions'] as List? ?? const []) {
          final ex=_map(rawEx);
          exceptions.add(EventException(
            eventId:ex['event_id'] as int,
            originalStart:fromDbDate(ex['original_start_at'] as String),
            type:ex['exception_type'] as String,
            overrideStart:ex['override_start_at']==null ? null : fromDbDate(ex['override_start_at'] as String),
            overrideEnd:ex['override_end_at']==null ? null : fromDbDate(ex['override_end_at'] as String),
            overrideTitle:ex['override_title'] as String?,
          ));
        }
      }
      if (page.length < 500) break;
    }
    final rawSettings=_map(await api.request('GET','/api/settings'));
    return AppSnapshot(events:events,categories:categories,exceptions:exceptions,
      settings:rawSettings.map((k,v)=>MapEntry(k,v.toString())));
  }

  @override
  Future<int> create(EventItem item) async {
    final created = _map(await api.request('POST','/api/events',data:_writeEvent(item)));
    return created['id'] as int;
  }

  @override
  Future<void> update(EventItem item) async {
    if(item.id==null) throw ArgumentError('Відсутній ID події');
    await api.request('PATCH','/api/events/${item.id}',data:_writeEvent(item));
  }

  @override
  Future<void> delete(int id) async {await api.request('DELETE','/api/events/$id');}

  @override
  Future<void> overrideOccurrence(EventException e) async {
    await api.request('PUT','/api/events/${e.eventId}/exceptions',data:{
      'original_start_at':toDbDate(e.originalStart),'exception_type':e.type,
      'override_start_at':e.overrideStart==null ? null : toDbDate(e.overrideStart!),
      'override_end_at':e.overrideEnd==null ? null : toDbDate(e.overrideEnd!),
      'override_title':e.overrideTitle,
    });
  }

  @override
  Future<void> setStatus(EventOccurrence occurrence,String status) async {
    if(!['DONE','MISSED','PLANNED'].contains(status)) throw ArgumentError.value(status);
    final id=occurrence.event.id!;
    if(occurrence.event.recurrence==null) {
      await api.request('PATCH','/api/events/$id',data:{'status':status});
    } else if(status=='PLANNED') {
      await api.request('DELETE',
        '/api/events/$id/exceptions?original_start_at=${Uri.encodeQueryComponent(toDbDate(occurrence.originalStart))}');
    } else {
      await overrideOccurrence(EventException(eventId:id,
        originalStart:occurrence.originalStart,type:status));
    }
  }

  @override
  Future<void> createCategory(String name,String colorHex) async {
    await api.request('POST','/api/categories',data:{'name':name,'color_hex':colorHex});
  }
  @override
  Future<void> updateCategory(Category c) async {
    await api.request('PUT','/api/categories/${c.id}',
      data:{'name':c.name,'color_hex':c.colorHex});
  }
  @override
  Future<void> deleteCategory(int id) async {await api.request('DELETE','/api/categories/$id');}
  @override
  Future<void> setSetting(String key,String value) async {
    if (key != 'theme') throw UnsupportedError('Невідоме налаштування');
    await api.request('PUT','/api/settings/theme',data:{'value':value});
  }
  @override
  Future<String> exportJson() async => throw UnsupportedError(
    'JSON-резервне копіювання доступне лише в офлайн-режимі');
  @override
  Future<void> importJson(String json) async => throw UnsupportedError(
    'Імпорт локальної SQLite до сервера не підтримується автоматично');
}
