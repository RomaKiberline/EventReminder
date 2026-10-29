import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  final String? testPath;
  AppDatabase({this.testPath});
  Database? _db;
  Future<Database> get connection async => _db ??= await _open();

  Future<Database> _open() async {
    if (testPath != null || Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final String path;
    if(testPath!=null) {path=testPath!;}
    else {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      path = p.join(support.path, 'event_reminder.sqlite');
    }
    return databaseFactory.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in schemaStatements) { await db.execute(sql); }
        final preset = <String,String>{
          'Навчання':'#2878C8','Робота':'#DB8745',
          'Особисте':'#7956B3','Здоров’я':'#31967B',
        };
        for (final entry in preset.entries) {
          await db.insert('categories',{'name':entry.key,'color_hex':entry.value});
        }
        await db.insert('app_settings', {'setting_key':'theme','setting_value':'system'});
      },
    ));
  }
  static const schemaStatements = <String>[
    '''CREATE TABLE categories (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK(length(trim(name)) BETWEEN 1 AND 60),
      color_hex TEXT NOT NULL CHECK(length(color_hex)=7 AND substr(color_hex,1,1)='#'))''',
    '''CREATE TABLE recurrence_rules (
      id INTEGER PRIMARY KEY,
      frequency TEXT NOT NULL CHECK(frequency IN ('DAILY','WEEKLY','MONTHLY')),
      interval_value INTEGER NOT NULL DEFAULT 1 CHECK(interval_value>=1),
      until_date TEXT, occurrence_count INTEGER CHECK(occurrence_count>0),
      CHECK(until_date IS NULL OR occurrence_count IS NULL))''',
    '''CREATE TABLE recurrence_weekdays (
      rule_id INTEGER NOT NULL, weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
      PRIMARY KEY(rule_id,weekday),
      FOREIGN KEY(rule_id) REFERENCES recurrence_rules(id) ON DELETE CASCADE)''',
    '''CREATE TABLE events (
      id INTEGER PRIMARY KEY,
      title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 150),
      description TEXT, location TEXT, start_at TEXT NOT NULL, end_at TEXT,
      status TEXT NOT NULL DEFAULT 'PLANNED' CHECK(status IN ('PLANNED','DONE','MISSED')),
      category_id INTEGER, recurrence_rule_id INTEGER UNIQUE,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
      CHECK(end_at IS NULL OR end_at>=start_at),
      FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
      FOREIGN KEY(recurrence_rule_id) REFERENCES recurrence_rules(id) ON DELETE RESTRICT)''',
    '''CREATE TABLE reminders (
      id INTEGER PRIMARY KEY, event_id INTEGER NOT NULL,
      offset_minutes INTEGER NOT NULL CHECK(offset_minutes>=0),
      is_enabled INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0,1)),
      snoozed_until TEXT, UNIQUE(event_id,offset_minutes),
      FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE)''',
    '''CREATE TABLE event_exceptions (
      event_id INTEGER NOT NULL, original_start_at TEXT NOT NULL,
      exception_type TEXT NOT NULL CHECK(exception_type IN ('MODIFIED','CANCELLED','DONE','MISSED')),
      override_start_at TEXT, override_end_at TEXT, override_title TEXT,
      PRIMARY KEY(event_id,original_start_at),
      CHECK(override_end_at IS NULL OR (override_start_at IS NOT NULL AND override_end_at>=override_start_at)),
      CHECK(exception_type='MODIFIED' OR (override_start_at IS NULL AND override_end_at IS NULL AND override_title IS NULL)),
      FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE)''',
    '''CREATE TABLE app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)''',
    'CREATE INDEX idx_events_start ON events(start_at)',
    'CREATE INDEX idx_events_category_start ON events(category_id,start_at)',
    'CREATE INDEX idx_reminders_event ON reminders(event_id)',
    'CREATE INDEX idx_event_exceptions_type ON event_exceptions(exception_type)',
  ];
}
