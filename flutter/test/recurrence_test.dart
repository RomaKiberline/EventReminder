import 'package:flutter_test/flutter_test.dart';
import 'package:event_reminder/domain/models.dart';
import 'package:event_reminder/domain/recurrence.dart';

void main() {
  test('daily recurrence respects count', () {
    final e=EventItem(id:1,title:'Щоденна подія',start:DateTime(2026,10,15,8),
      recurrence:const RecurrenceRule(frequency:'DAILY',count:3));
    final list=expandOccurrences(e,[],DateTime(2026,10,1),DateTime(2026,11,1));
    expect(list.map((e)=>e.start.day),[15,16,17]);
  });
  test('weekly weekdays match 1 and 3', () {
    final e=EventItem(id:2,title:'Пара',start:DateTime(2026,10,19,9),
      recurrence:const RecurrenceRule(frequency:'WEEKLY',weekdays:[1,3],count:4));
    final list=expandOccurrences(e,[],DateTime(2026,10,1),DateTime(2026,11,1));
    expect(list.map((e)=>e.start.day),[19,21,26,28]);
  });
  test('monthly date 31 skips missing dates', () {
    final e=EventItem(id:3,title:'Звіт',start:DateTime(2026,1,31,12),
      recurrence:const RecurrenceRule(frequency:'MONTHLY',count:3));
    final list=expandOccurrences(e,[],DateTime(2026,1),DateTime(2026,6));
    expect(list.map((e)=>e.start.month),[1,3,5]);
  });
  test('edited and cancelled occurrence', () {
    final e=EventItem(id:4,title:'Зустріч',start:DateTime(2026,10,15,8),
      recurrence:const RecurrenceRule(frequency:'DAILY',count:3));
    final ex=[
      EventException(eventId:4,originalStart:DateTime(2026,10,16,8),
        type:'MODIFIED',overrideStart:DateTime(2026,10,16,11),overrideTitle:'Нова зустріч'),
      EventException(eventId:4,originalStart:DateTime(2026,10,17,8),type:'CANCELLED'),
    ];
    final list=expandOccurrences(e,ex,DateTime(2026,10,15),DateTime(2026,10,20));
    expect(list.length,2); expect(list.last.title,'Нова зустріч');
    expect(list.last.start.hour,11);
  });
}
