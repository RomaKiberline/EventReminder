import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';
import '../domain/repository.dart';
import 'sqlite_database.dart';

class SqliteEventRepository implements IEventRepository {
  final AppDatabase database;
  SqliteEventRepository(this.database);
  Future<Database> get _db => database.connection;

  @override
  Future<AppSnapshot> loadAll() async {
    final db = await _db;
    final categoryRows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    final ruleRows = await db.query('recurrence_rules');
    final weekRows = await db.query('recurrence_weekdays');
    final reminderRows = await db.query('reminders', where:'is_enabled=1');
    final eventRows = await db.query('events');
    final exceptionRows = await db.query('event_exceptions');
    final settingsRows = await db.query('app_settings');
    final weekdays = <int,List<int>>{};
    for (final row in weekRows) {
      (weekdays[row['rule_id'] as int] ??= []).add(row['weekday'] as int);
    }
    final rules = <int,RecurrenceRule>{};
    for (final row in ruleRows) {
      final id = row['id'] as int;
      rules[id] = RecurrenceRule(id:id, frequency:row['frequency'] as String,
        interval: row['interval_value'] as int,
        until:row['until_date'] == null ? null : DateTime.parse(row['until_date'] as String),
        count:row['occurrence_count'] as int?, weekdays:weekdays[id] ?? []);
    }
    final offsets = <int,List<int>>{};
    for (final row in reminderRows) {
      (offsets[row['event_id'] as int] ??= []).add(row['offset_minutes'] as int);
    }
    final events = <EventItem>[];
    for (final row in eventRows) {
      final id = row['id'] as int;
      final ruleId = row['recurrence_rule_id'] as int?;
      events.add(EventItem(id:id, title:row['title'] as String,
        description:(row['description'] as String?) ?? '',
        location:(row['location'] as String?) ?? '',
        start:fromDbDate(row['start_at'] as String),
        end:row['end_at'] == null ? null : fromDbDate(row['end_at'] as String),
        status:row['status'] as String, categoryId:row['category_id'] as int?,
        recurrence:ruleId == null ? null : rules[ruleId],
        reminderOffsets:offsets[id] ?? []));
    }
    return AppSnapshot(
      events:events,
      categories:[for (final row in categoryRows)
        Category(row['id'] as int,row['name'] as String,row['color_hex'] as String)],
      exceptions:[for (final row in exceptionRows)
        EventException(eventId:row['event_id'] as int,
          originalStart:fromDbDate(row['original_start_at'] as String),
          type:row['exception_type'] as String,
          overrideStart: row['override_start_at']==null ? null : fromDbDate(row['override_start_at'] as String),
          overrideEnd: row['override_end_at']==null ? null : fromDbDate(row['override_end_at'] as String),
          overrideTitle:row['override_title'] as String?)],
      settings:{for (final row in settingsRows)
        row['setting_key'] as String:row['setting_value'] as String},
    );
  }

  Map<String,Object?> _eventRow(EventItem e, int? ruleId) => {
    'title':e.title.trim(), 'description':e.description.trim(), 'location':e.location.trim(),
    'start_at':toDbDate(e.start), 'end_at':e.end == null ? null : toDbDate(e.end!),
    'status':e.status,'category_id':e.categoryId,'recurrence_rule_id':ruleId,
  };

  Future<int?> _saveRule(Transaction txn, RecurrenceRule? rule, int? oldRule) async {
    if (rule == null) return null;
    final row = <String,Object?>{
      'frequency':rule.frequency,'interval_value':rule.interval,
      'until_date':rule.until == null ? null
        : '${rule.until!.year.toString().padLeft(4,'0')}-${rule.until!.month.toString().padLeft(2,'0')}-${rule.until!.day.toString().padLeft(2,'0')}',
      'occurrence_count':rule.count,
    };
    final int id;
    if (oldRule == null) {
      id = await txn.insert('recurrence_rules',row);
    } else {
      id = oldRule;
      await txn.update('recurrence_rules',row,where:'id=?',whereArgs:[id]);
      await txn.delete('recurrence_weekdays',where:'rule_id=?',whereArgs:[id]);
    }
    for (final weekday in rule.weekdays.toSet()) {
      await txn.insert('recurrence_weekdays',{'rule_id':id,'weekday':weekday});
    }
    return id;
  }

  Future<void> _replaceReminders(Transaction txn, int eventId, List<int> reminders) async {
    await txn.delete('reminders',where:'event_id=?',whereArgs:[eventId]);
    for (final offset in reminders.toSet()) {
      await txn.insert('reminders',{'event_id':eventId,'offset_minutes':offset});
    }
  }

  void _validate(EventItem e) {
    if (!e.valid || e.title.trim().length>150) throw const FormatException('Перевір назву та час події');
  }

  @override
  Future<int> create(EventItem item) async {
    _validate(item);
    final db = await _db;
    return db.transaction((txn) async {
      final ruleId = await _saveRule(txn,item.recurrence,null);
      final id = await txn.insert('events',_eventRow(item,ruleId));
      await _replaceReminders(txn,id,item.reminderOffsets);
      return id;
    });
  }

  @override
  Future<void> update(EventItem item) async {
    _validate(item);
    if (item.id == null) throw ArgumentError('Подія не має id');
    final db = await _db;
    await db.transaction((txn) async {
      final row = await txn.query('events',columns:['recurrence_rule_id'],where:'id=?',whereArgs:[item.id]);
      if (row.isEmpty) throw StateError('Подію не знайдено');
      final oldRule = row.first['recurrence_rule_id'] as int?;
      final newRule = await _saveRule(txn,item.recurrence,oldRule);
      await txn.update('events',_eventRow(item,newRule),where:'id=?',whereArgs:[item.id]);
      if (oldRule != null && newRule == null) {
        await txn.delete('recurrence_rules',where:'id=?',whereArgs:[oldRule]);
      }
      if (item.recurrence == null) {
        await txn.delete('event_exceptions',where:'event_id=?',whereArgs:[item.id]);
      }
      await _replaceReminders(txn,item.id!,item.reminderOffsets);
    });
  }

  @override
  Future<void> delete(int id) async {
    final db=await _db;
    await db.transaction((txn) async {
      final r=await txn.query('events',columns:['recurrence_rule_id'],where:'id=?',whereArgs:[id]);
      if(r.isEmpty) return;
      await txn.delete('events',where:'id=?',whereArgs:[id]);
      final ruleId=r.first['recurrence_rule_id'] as int?;
      if(ruleId!=null) await txn.delete('recurrence_rules',where:'id=?',whereArgs:[ruleId]);
    });
  }

  @override
  Future<void> overrideOccurrence(EventException e) async {
    final db = await _db;
    await db.insert('event_exceptions',{
      'event_id':e.eventId,'original_start_at':toDbDate(e.originalStart),
      'exception_type':e.type,
      'override_start_at':e.overrideStart == null ? null : toDbDate(e.overrideStart!),
      'override_end_at':e.overrideEnd == null ? null : toDbDate(e.overrideEnd!),
      'override_title':e.overrideTitle,
    },conflictAlgorithm:ConflictAlgorithm.replace);
  }

  @override
  Future<void> setStatus(EventOccurrence occurrence,String status) async {
    if (!['DONE','MISSED','PLANNED'].contains(status)) throw ArgumentError.value(status);
    final db=await _db;
    if (occurrence.event.recurrence == null) {
      await db.update('events',{'status':status},where:'id=?',whereArgs:[occurrence.event.id]);
    } else if (status == 'PLANNED') {
      await db.delete('event_exceptions',where:'event_id=? AND original_start_at=?',
        whereArgs:[occurrence.event.id,toDbDate(occurrence.originalStart)]);
    } else {
      await overrideOccurrence(EventException(eventId:occurrence.event.id!,
        originalStart:occurrence.originalStart,type:status));
    }
  }

  @override
  Future<void> createCategory(String name,String colorHex) async {
    final db=await _db;
    await db.insert('categories',{'name':name.trim(),'color_hex':colorHex});
  }
  @override
  Future<void> updateCategory(Category c) async {
    final db=await _db;
    await db.update('categories',{'name':c.name.trim(),'color_hex':c.colorHex},where:'id=?',whereArgs:[c.id]);
  }
  @override
  Future<void> deleteCategory(int id) async {
    final db=await _db;
    await db.delete('categories',where:'id=?',whereArgs:[id]);
  }
  @override
  Future<void> setSetting(String key,String value) async {
    final db=await _db;
    await db.insert('app_settings',{'setting_key':key,'setting_value':value},
      conflictAlgorithm:ConflictAlgorithm.replace);
  }

  static const tables = [
    'categories','recurrence_rules','recurrence_weekdays','events',
    'reminders','event_exceptions','app_settings',
  ];
  @override
  Future<String> exportJson() async {
    final db=await _db;
    final rows=<String,dynamic>{};
    for (final table in tables) { rows[table]=await db.query(table); }
    return const JsonEncoder.withIndent('  ').convert({
      'format':'event_reminder_backup','schemaVersion':1,'tables':rows,
    });
  }
  @override
  Future<void> importJson(String jsonText) async {
    final decoded=jsonDecode(jsonText);
    if(decoded is! Map || decoded['format']!='event_reminder_backup' ||
      decoded['schemaVersion']!=1 || decoded['tables'] is! Map) {
      throw const FormatException('Непідтримуваний файл резервної копії');
    }
    final rawTables=decoded['tables'] as Map;
    for (final name in tables) {
      if (rawTables[name] is! List) throw FormatException('Немає таблиці $name');
      for(final row in rawTables[name] as List) {
        if(row is! Map) throw FormatException('Пошкоджено таблицю $name');
      }
    }
    final db=await _db;
    // Atomic replacement: any invalid row rolls back every deletion/insert.
    await db.transaction((txn) async {
      for (final table in tables.reversed) { await txn.delete(table); }
      for (final table in tables) {
        for (final item in rawTables[table] as List) {
          await txn.insert(table,Map<String,Object?>.from(item as Map));
        }
      }
    });
  }
}
