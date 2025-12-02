import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'memo_model.dart';
import 'calendar_event_model.dart';
import 'memory_item.dart';
import 'user_profile.dart';
import 'feedback_module.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  handleFeedback(response);
}

@pragma('vm:entry-point')
Future<void> handleFeedback(NotificationResponse response) async {
  await AlarmService().processFeedback(
    response.payload,
    int.tryParse(response.actionId ?? ''),
  );
}

class MemoryConverter {
  static MemoryItem fromMemo(Memo memo, UserProfile userProfile) {
    final String combinedContent = "[메모] ${memo.title}\n${memo.content}";
    return MemoryItem.initial(
      id: 'MEMO_${memo.id}',
      content: combinedContent,
      initialEf: userProfile.globalEf,
    );
  }

  static MemoryItem fromCalendarEvent(
      CalendarEvent event, UserProfile userProfile) {
    final String dateStr =
        "${event.startDate.month}/${event.startDate.day} ${event.startDate.hour}:${event.startDate.minute}";
    final String combinedContent =
        "[일정] ${event.title}\n($dateStr) ${event.description ?? ''}";
    return MemoryItem.initial(
      id: 'EVENT_${event.id}',
      content: combinedContent,
      initialEf: userProfile.globalEf,
    );
  }
}

class AlarmService {
  static const String _storageKey = 'memory_items';

  static final StreamController<void> dataUpdateStream =
  StreamController.broadcast();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  AlarmService() {
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();

    try {
      // flutter_timezone 5.x : TimezoneInfo.identifier 사용
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('타임존 설정 실패: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        handleFeedback(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  Future<List<MemoryItem>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final jsonList = prefs.getStringList(_storageKey) ?? [];
    return jsonList
        .map((jsonStr) => MemoryItem.fromJson(jsonDecode(jsonStr)))
        .toList();
  }

  Future<void> _saveItems(List<MemoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  Future<MemoryItem?> getMemoryItem(String itemId) async {
    final List<MemoryItem> items = await _loadItems();
    try {
      return items.firstWhere((item) => item.id == itemId);
    } catch (e) {
      return null;
    }
  }

  Future<MemoryItem?> processFeedback(String? itemId, int? score) async {
    if (itemId == null || score == null) return null;

    WidgetsFlutterBinding.ensureInitialized();
    print('Feedback 처리 시작: 아이템 $itemId, 점수 $score');

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: initializationSettingsAndroid),
    );

    await flutterLocalNotificationsPlugin.cancel(itemId.hashCode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final jsonList = prefs.getStringList(_storageKey) ?? [];
    List<MemoryItem> items =
    jsonList.map((jsonStr) => MemoryItem.fromJson(jsonDecode(jsonStr))).toList();

    final int index = items.indexWhere((item) => item.id == itemId);
    if (index == -1) {
      print('Feedback 아이템을 찾을 수 없음: $itemId');
      return null;
    }

    final feedbackModule = FeedbackModule();
    final updatedItem = feedbackModule.schedule(items[index], score);
    items[index] = updatedItem;

    final int nextSeconds = updatedItem.interval * 10;
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('피드백 반영 완료');
    print('점수: $score / EF: ${updatedItem.ef.toStringAsFixed(2)}');
    print('다음 알림: $nextSeconds초 뒤 (${updatedItem.nextReviewDate})');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final newJsonList = items.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_storageKey, newJsonList);

    AlarmService.dataUpdateStream.add(null);

    tz.initializeTimeZones();
    try {
      // 여기서도 동일하게 identifier 사용
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('타임존 재설정 실패: $e');
    }

    if (updatedItem.nextReviewDate.isAfter(DateTime.now())) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        updatedItem.id.hashCode,
        '복습할 시간입니다!',
        updatedItem.content.split('\n').first,
        tz.TZDateTime.from(updatedItem.nextReviewDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'memory_channel_v3',
            '기억 복습 알림',
            channelDescription: '에빙하우스 망각곡선 기반 복습 알림입니다.',
            importance: Importance.max,
            priority: Priority.high,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                '1',
                '다시(1점)',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                '3',
                '보통(3점)',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                '5',
                '완벽(5점)',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: itemId,
      );
    }
    return updatedItem;
  }

  Future<void> _scheduleNotification(MemoryItem item) async {
    final int notificationId = item.id.hashCode;
    if (item.nextReviewDate.isBefore(DateTime.now())) return;

    final AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'memory_channel_v3',
      '기억 복습 알림',
      channelDescription: '에빙하우스 망각곡선 기반 복습 알림입니다.',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          '1',
          '다시(1점)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          '3',
          '보통(3점)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          '5',
          '완벽(5점)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _notificationsPlugin.zonedSchedule(
      notificationId,
      '복습할 시간입니다!',
      item.content.split('\n').first,
      tz.TZDateTime.from(item.nextReviewDate, tz.local),
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      payload: item.id,
    );
  }

  Future<void> _cancelNotification(String itemId) async {
    await _notificationsPlugin.cancel(itemId.hashCode);
  }

  Future<void> showInstantNotification() async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'memory_channel_v3',
      '기억 복습 알림',
      channelDescription: '즉시 알림 테스트입니다.',
      importance: Importance.max,
      priority: Priority.high,
    );
    await _notificationsPlugin.show(
      0,
      '즉시 알림 테스트',
      '설정이 정상적으로 완료되었습니다.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> saveMemo(Memo memo, UserProfile userProfile) async {
    final List<MemoryItem> items = await _loadItems();
    final String targetId = 'MEMO_${memo.id}';
    final int index = items.indexWhere((item) => item.id == targetId);
    MemoryItem itemToSave;

    if (index != -1) {
      itemToSave = items[index].copyWith(
        content: MemoryConverter.fromMemo(memo, userProfile).content,
      );
      items[index] = itemToSave;
    } else {
      itemToSave = MemoryConverter.fromMemo(memo, userProfile);
      items.add(itemToSave);
    }
    await _saveItems(items);
    await showInstantNotification();
    await _scheduleNotification(itemToSave);
  }

  Future<void> deleteMemo(String memoId) async {
    final List<MemoryItem> items = await _loadItems();
    final String targetId = 'MEMO_$memoId';
    items.removeWhere((item) => item.id == targetId);
    await _saveItems(items);
    await _cancelNotification(targetId);
  }

  Future<void> saveEvent(
      CalendarEvent event, UserProfile userProfile) async {
    final List<MemoryItem> items = await _loadItems();
    final String targetId = 'EVENT_${event.id}';
    final int index = items.indexWhere((item) => item.id == targetId);
    MemoryItem itemToSave;

    if (index != -1) {
      itemToSave = items[index].copyWith(
        content: MemoryConverter.fromCalendarEvent(event, userProfile).content,
      );
      items[index] = itemToSave;
    } else {
      itemToSave = MemoryConverter.fromCalendarEvent(event, userProfile);
      items.add(itemToSave);
    }
    await _saveItems(items);
    await _scheduleNotification(itemToSave);
  }

  Future<void> deleteEvent(String eventId) async {
    final List<MemoryItem> items = await _loadItems();
    final String targetId = 'EVENT_$eventId';
    items.removeWhere((item) => item.id == targetId);
    await _saveItems(items);
    await _cancelNotification(targetId);
  }
}
