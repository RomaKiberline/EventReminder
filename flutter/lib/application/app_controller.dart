import 'package:flutter/foundation.dart' show ChangeNotifier;
import '../domain/models.dart';
import '../domain/recurrence.dart';
import '../domain/repository.dart';
import '../infrastructure/notification_service.dart';

class AppController extends ChangeNotifier {
  final IEventRepository repository;
  final NotificationService notifications;
  AppController(this.repository,this.notifications);
  AppSnapshot snapshot=const AppSnapshot(events:[],categories:[],exceptions:[],settings:{});
  bool ready=false;
  String? error;
  int? pendingEvent;

  List<Category> get categories => snapshot.categories;
  List<EventItem> get events => snapshot.events;
  String get theme => snapshot.settings['theme'] ?? 'system';
  String? notificationWarning;

  Future<void> initialize() async {
    try {
      await notifications.initialize();
      notifications.onOpenEvent=(id){ pendingEvent=id; notifyListeners(); };
      pendingEvent=notifications.pendingOpenEventId;
      await reload();
    } catch(e) { error=e.toString(); ready=true; notifyListeners(); }
  }
  Future<void> reload() async {
    snapshot=await repository.loadAll();
    ready=true;
    notifyListeners();
    notificationWarning=await notifications.synchronize(snapshot);
    notifyListeners();
  }

  List<EventOccurrence> between(DateTime from,DateTime to) {
    final items=<EventOccurrence>[];
    for(final event in events) {
      items.addAll(expandOccurrences(event,snapshot.exceptions,from,to));
    }
    items.sort((a,b)=>a.start.compareTo(b.start));
    return items;
  }
  Category? categoryOf(int? id) {
    for(final c in categories) { if(c.id==id) return c; }
    return null;
  }
  EventItem? findEvent(int id) {
    for(final e in events) { if(e.id==id) return e; }
    return null;
  }
  void clearPending() { pendingEvent=null; notifications.pendingOpenEventId=null; }

  Future<void> save(EventItem item) async {
    if(item.id==null) { await repository.create(item); }
    else { await repository.update(item); }
    await reload();
  }
  Future<void> editOccurrence(EventException exception) async {
    await repository.overrideOccurrence(exception); await reload();
  }
  Future<void> deleteOccurrence(EventOccurrence occurrence,{required bool wholeSeries}) async {
    if(wholeSeries || occurrence.event.recurrence==null) {
      await repository.delete(occurrence.event.id!);
    } else {
      await repository.overrideOccurrence(EventException(eventId:occurrence.event.id!,
        originalStart:occurrence.originalStart,type:'CANCELLED'));
    }
    await reload();
  }
  Future<void> changeStatus(EventOccurrence occ,String status) async {
    await repository.setStatus(occ,status);await reload();
  }
  Future<void> addCategory(String name,String hex) async {
    await repository.createCategory(name,hex);await reload();
  }
  Future<void> editCategory(Category c) async {
    await repository.updateCategory(c);await reload();
  }
  Future<void> removeCategory(int id) async {
    await repository.deleteCategory(id);await reload();
  }
  Future<void> setTheme(String theme) async {
    await repository.setSetting('theme',theme);await reload();
  }
  Future<void> importJson(String json) async {
    await repository.importJson(json);await reload();
  }
}
