import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Alarm-style notification config with custom alarm sound.
  AndroidNotificationDetails get _alarmDetails => AndroidNotificationDetails(
        'medicine_alarm_v5',
        'Medicine Alarms',
        channelDescription: 'Alarm reminders to take medicine',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_tone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        autoCancel: false,
        ongoing: true,
        visibility: NotificationVisibility.public,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('taken', 'Taken',
              showsUserInterface: true),
          const AndroidNotificationAction('remind_later', 'Remind Later',
              showsUserInterface: true),
        ],
      );

  /// Silent notification for confirmations (no sound/vibration).
  AndroidNotificationDetails get _silentDetails => const AndroidNotificationDetails(
        'medicine_info',
        'Medicine Info',
        channelDescription: 'General medicine information',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        autoCancel: true,
      );

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    print('[AlarmService] Timezone set to: ${tz.local}');

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
    );

    // Request notification permission (Android 13+)
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final notifGranted =
          await androidPlugin.requestNotificationsPermission();
      print('[AlarmService] Notification permission granted: $notifGranted');

      final alarmGranted =
          await androidPlugin.requestExactAlarmsPermission();
      print('[AlarmService] Exact alarm permission granted: $alarmGranted');

      // Create alarm channel with custom sound
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'medicine_alarm_v5',
          'Medicine Alarms',
          description: 'Alarm reminders to take medicine',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_tone'),
          enableVibration: true,
        ),
      );
      print('[AlarmService] Alarm channel created: medicine_alarm_v5');

      // Create silent info channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'medicine_info',
          'Medicine Info',
          description: 'General medicine information',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );
      print('[AlarmService] Info channel created: medicine_info');
    }

    final initialized = await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse response) async {
        print('[AlarmService] Notification response: actionId=${response.actionId}, id=${response.id}');
        if (response.actionId == 'taken') {
          if (response.id != null) {
            await flutterLocalNotificationsPlugin.cancel(id: response.id!);
          }
        } else if (response.actionId == 'remind_later') {
          if (response.payload != null) {
            _scheduleRemindLater(response.payload!);
          }
        }
      },
    );
    print('[AlarmService] Plugin initialized: $initialized');
  }

  /// Show an alarm notification immediately (with sound + vibration).
  Future<void> showAlarmNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: _alarmDetails),
        payload: payload,
      );
      print('[AlarmService] 🔔 Alarm notification shown: id=$id');
    } catch (e) {
      print('[AlarmService ERROR] Failed to show alarm: $e');
    }
  }

  /// Show a silent info notification (no sound).
  Future<void> showInfoNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: _silentDetails),
      );
      print('[AlarmService] ℹ️ Info notification shown: id=$id');
    } catch (e) {
      print('[AlarmService ERROR] Failed to show info notification: $e');
    }
  }

  Future<void> _scheduleRemindLater(String payload) async {
    try {
      final remindTime =
          tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15));
      print('[AlarmService] Scheduling remind-later at $remindTime');
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: DateTime.now().millisecond,
        title: '💊 Medicine Reminder',
        body: 'Time to take your medicine!',
        scheduledDate: remindTime,
        notificationDetails: NotificationDetails(android: _alarmDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      print('[AlarmService ERROR] Failed to schedule remind-later: $e');
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String payload,
  }) async {
    final tzScheduled = tz.TZDateTime.from(scheduledTime, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    // Skip if time is in the past
    if (tzScheduled.isBefore(now)) {
      print('[AlarmService WARN] Skipping alarm id=$id — scheduled time '
          '$tzScheduled is in the past (now=$now)');
      return;
    }

    print('[AlarmService] Scheduling alarm id=$id at $tzScheduled for "$payload"');
    print('[AlarmService]   title: $title');
    print('[AlarmService]   body: $body');

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzScheduled,
        notificationDetails: NotificationDetails(android: _alarmDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      print('[AlarmService] ✓ Alarm id=$id scheduled successfully');
    } catch (e) {
      print('[AlarmService ERROR] Failed to schedule alarm id=$id: $e');
      rethrow;
    }
  }

  /// Cancel all scheduled notifications.
  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    print('[AlarmService] All notifications cancelled');
  }
}
