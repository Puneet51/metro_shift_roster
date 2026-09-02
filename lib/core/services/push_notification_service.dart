import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';

/// Must be a top-level function outside of any class
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel
  _highImportanceChannel = AndroidNotificationChannel(
    'metro_shift_high_importance_channel',
    'Metro Shift Urgent Alerts',
    description:
        'High-priority notifications for Shift assignments and lock-screen alerts.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  static Future<void> initialize() async {
    try {
      // 1. Set background handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // 2. Request runtime permissions for Android 13+ and iOS
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // 3. Setup Android Local Channel for heads-up and lock-screen visibility
      await _localPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_highImportanceChannel);

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const initSettings = InitializationSettings(android: androidSettings);

      await _localPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle tap action if needed
        },
      );

      // 4. Foreground listener (Shows Heads-Up Banner when app is open)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          _localPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _highImportanceChannel.id,
                _highImportanceChannel.name,
                channelDescription: _highImportanceChannel.description,
                importance: Importance.max,
                priority: Priority.high,
                visibility:
                    NotificationVisibility.public, // Visible on Lock Screen
                icon: android.smallIcon ?? '@mipmap/launcher_icon',
              ),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('PushNotificationService initialization error: $e');
    }
  }

  /// Syncs the device's FCM push token to the user's Supabase profile
  static Future<void> syncFCMToken(String userId) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await SupabaseService.client
            .from('profiles')
            .update({
              'fcm_token': token,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId);
      }

      // Listen for periodic token refreshes
      _fcm.onTokenRefresh.listen((newToken) async {
        try {
          await SupabaseService.client
              .from('profiles')
              .update({
                'fcm_token': newToken,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', userId);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('FCM Token sync skipped/failed: $e');
    }
  }
}
