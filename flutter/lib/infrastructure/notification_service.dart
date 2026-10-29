import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
import '../domain/recurrence.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin=FlutterLocalNotificationsPlugin();
  void Function(int eventId)? onOpenEvent;
  int? pendingOpenEventId;
  bool _initialized=false;
  AndroidScheduleMode _scheduleMode=AndroidScheduleMode.inexactAllowWhileIdle;
  bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<void> initialize() async {
    if(!supported) return; // Desktop remains a fully functional SQLite preview.
    tzdata.initializeTimeZones();
    const settings=InitializationSettings(
      android:AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS:DarwinInitializationSettings(requestAlertPermission:false,
        requestBadgePermission:false,requestSoundPermission:false),
    );
    await _plugin.initialize(settings,onDidReceiveNotificationResponse:_onResponse);
    _initialized=true;
    final details=await _plugin.getNotificationAppLaunchDetails();
    if(details?.didNotificationLaunchApp==true && details?.notificationResponse!=null) {
      _onResponse(details!.notificationResponse!);
    }
    _initialized=true;
    if(Platform.isAndroid) {
      try {
        final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if(await android?.canScheduleExactNotifications()==true) {
          _scheduleMode=AndroidScheduleMode.exactAllowWhileIdle;
        }
      } catch (_) {}
    }
  }

  Future<bool> requestPermission() async {
    if(!_initialized) return false;
    if(Platform.isAndroid) {
      final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted=await android?.requestNotificationsPermission() ?? false;
      // Precise alarms are optional; if denied we fall back to inexact alarms.
      try {
        final exact=await android?.requestExactAlarmsPermission();
        if(exact==true) _scheduleMode=AndroidScheduleMode.exactAllowWhileIdle;
      } catch (_) {}
      return granted;
    }
    if(Platform.isIOS) {
      final ios=_plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert:true,badge:true,sound:true) ?? false;
    }
    return false;
  }

  void _onResponse(NotificationResponse response) {
    final payload=response.payload;
    if(payload==null) return;
    try {
      final obj=jsonDecode(payload) as Map<String,dynamic>;
      final id=obj['event'] as int;
      if(response.actionId?.startsWith('snooze_')==true) {
        final minutes=int.tryParse(response.actionId!.replaceFirst('snooze_','')) ?? 10;
        _snooze(id,(obj['id'] as int?) ?? 1,minutes,obj['title'] as String? ?? 'Нагадування');
      } else {
        pendingOpenEventId=id;
        onOpenEvent?.call(id);
      }
    } catch (_) { /* Ignore payloads from other app versions. */ }
  }
  Future<void> _snooze(int eventId,int originalNotificationId,int minutes,String title) async {
    if(!_initialized) return;
    try {
      await _plugin.zonedSchedule(100000+originalNotificationId,title,
        'Відкладене нагадування',
        tz.TZDateTime.from(DateTime.now().add(Duration(minutes:minutes)),tz.UTC),
        _details, androidScheduleMode:_scheduleMode,
        payload:jsonEncode({'event':eventId,'id':originalNotificationId,'title':title}));
    } catch (_) {}
  }

  static const _details=NotificationDetails(
    android:AndroidNotificationDetails('personal_events','Особисті події',
      channelDescription:'Нагадування про заплановані події',
      importance:Importance.high,priority:Priority.high,
      visibility:NotificationVisibility.public,
      actions:[
        AndroidNotificationAction('snooze_5','+5 хв',showsUserInterface:true),
        AndroidNotificationAction('snooze_10','+10 хв',showsUserInterface:true),
        AndroidNotificationAction('snooze_15','+15 хв',showsUserInterface:true),
      ]),
    iOS:DarwinNotificationDetails(presentAlert:true,presentBadge:true,presentSound:true),
  );

  /// On mobile, keep a rolling window of up to 60 pending notices (iOS limit 64).
  /// Call whenever events change and after an import.
  Future<String?> synchronize(AppSnapshot data) async {
    if(!_initialized) return null;
    try {
      await _plugin.cancelAll();
      final now=DateTime.now();
      final all=<({EventOccurrence occurrence, DateTime at, int offset})>[];
      for(final event in data.events) {
        if(event.reminderOffsets.isEmpty) continue;
        final occurrences=expandOccurrences(event,data.exceptions,
          now.subtract(const Duration(days:2)),now.add(const Duration(days:90)));
        for(final occurrence in occurrences) {
          if(occurrence.status!='PLANNED') continue;
          for(final offset in event.reminderOffsets) {
            final at=occurrence.start.subtract(Duration(minutes:offset));
            if(at.isAfter(now)) all.add((occurrence:occurrence,at:at,offset:offset));
          }
        }
      }
      all.sort((x,y)=>x.at.compareTo(y.at));
      for(var i=0;i<all.length && i<60;i++) {
        final item=all[i];
        final id=i+1;
        final payload=jsonEncode({'event':item.occurrence.event.id,
          'original':toDbDate(item.occurrence.originalStart),
          'id':id,'title':item.occurrence.title});
        await _plugin.zonedSchedule(id,item.occurrence.title,
          DateFormat('dd.MM о HH:mm').format(item.occurrence.start),
          tz.TZDateTime.from(item.at,tz.UTC),_details,
          androidScheduleMode:_scheduleMode,
          payload:payload);
      }
      return null;
    } catch (error) {
      return 'Нагадування не вдалося запланувати: $error';
    }
  }
}
