import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localPlugin.initialize(initSettings);
  }

  /// Show instant banner notification
  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'metro_shift_channel',
      'Shift & Duty Alerts',
      channelDescription:
          'Notifications for shift assignments, punch updates, and rosters',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);
    await _localPlugin.show(id, title, body, details);
  }

  /// Realtime Stream to listen for user notifications from Supabase
  static RealtimeChannel subscribeToUserNotifications(
    String userId,
    Function(Map<String, dynamic>) onNewNotification,
  ) {
    return SupabaseService.client
        .channel('public:notifications:user_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            showLocalNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: newRecord['title'] ?? 'Metro Shift Alert',
              body:
                  newRecord['body'] ?? 'You have a new update in your roster.',
            );
            onNewNotification(newRecord);
          },
        )..subscribe();
  }
}
