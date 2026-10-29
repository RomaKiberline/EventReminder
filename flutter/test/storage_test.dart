import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:event_reminder/data/sqlite_database.dart';
import 'package:event_reminder/data/sqlite_event_repository.dart';
import 'package:event_reminder/domain/models.dart';
import 'package:event_reminder/domain/recurrence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SQLite CRUD, recurrence, category, backup and restore', () async {
    final storage=SqliteEventRepository(AppDatabase(testPath:inMemoryDatabasePath));
    final start=DateTime(2026,10,19,12);
    final id=await storage.create(EventItem(title:'Лабораторна №5',start:start,
      categoryId:1,reminderOffsets:[15,60],
      recurrence:const RecurrenceRule(frequency:'WEEKLY',weekdays:[1,3],count:4)));
    var state=await storage.loadAll();
    expect(state.events.length,1);
    expect(state.events.first.reminderOffsets.length,2);
    final occ=expandOccurrences(state.events.first,[],DateTime(2026,10,1),DateTime(2026,11,1));
    expect(occ.length,4);
    await storage.overrideOccurrence(EventException(eventId:id,
      originalStart:occ[1].originalStart,type:'CANCELLED'));
    state=await storage.loadAll();
    expect(expandOccurrences(state.events.first,state.exceptions,
      DateTime(2026,10,1),DateTime(2026,11,1)).length,3);
    final copy=await storage.exportJson();
    await storage.delete(id);
    expect((await storage.loadAll()).events,isEmpty);
    await storage.importJson(copy);
    state=await storage.loadAll();
    expect(state.events.single.title,'Лабораторна №5');
    expect(state.exceptions.length,1);
    try {await storage.importJson('{"bad":true}');fail('Should reject invalid backup');}
    on FormatException { /* expected */ }
    expect((await storage.loadAll()).events.length,1);
  });
}
