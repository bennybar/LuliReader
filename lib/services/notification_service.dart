import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'database_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialize notification service and request permissions
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidInitializationSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
    );

    // Request permissions on iOS
    if (Platform.isIOS) {
      final bool? result = await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: false,
          );
      print('iOS notification permissions requested: $result');
    }

    // Create Android notification channel (required for Android 8.0+)
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        'lulireader_notifications',
        'LuliReader Notifications',
        description: 'Notifications for LuliReader app',
        importance: Importance.low, // Low importance for badge-only
        showBadge: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }

    _initialized = true;
    print('Notification service initialized');
  }

  /// Update app icon badge with unread article count
  static Future<void> updateBadgeCount() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final db = DatabaseService();
      final unreadCount = await db.getUnreadCount();

      if (Platform.isIOS) {
        // iOS badge update using platform channel
        try {
          const platform = MethodChannel('lulireader.app/badge');
          await platform.invokeMethod('setBadge', unreadCount);
        } catch (e) {
          print('Error setting iOS badge via platform channel: $e');
          // Fallback: use notification service
          final iosPlugin = _localNotifications
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>();
          
          if (iosPlugin != null) {
            await iosPlugin.requestPermissions(badge: true);
          }
        }
      } else if (Platform.isAndroid) {
        // Android badge update - use notification with number
        final androidDetails = AndroidNotificationDetails(
          'lulireader_notifications',
          'LuliReader Notifications',
          channelDescription: 'Notifications for LuliReader app',
          importance: Importance.low,
          priority: Priority.low,
          showWhen: false,
          onlyAlertOnce: true,
          ongoing: false,
          autoCancel: false,
        );

        final notificationDetails = NotificationDetails(
          android: androidDetails,
        );

        // Show a silent notification with badge count
        // Android launchers will show the badge count from the notification number
        await _localNotifications.show(
          999999, // Fixed ID for badge-only notification
          unreadCount > 0 ? '$unreadCount unread' : null, // Title only if there are unread
          null, // No body
          notificationDetails,
        );
      }

      print('Badge count updated to: $unreadCount');
    } catch (e) {
      print('Error updating badge count: $e');
    }
  }

  /// Clear badge count
  static Future<void> clearBadge() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      if (Platform.isIOS) {
        // Use platform channel to clear badge
        try {
          const platform = MethodChannel('lulireader.app/badge');
          await platform.invokeMethod('setBadge', 0);
        } catch (e) {
          print('Error clearing iOS badge via platform channel: $e');
        }
      } else {
        // Cancel the badge notification on Android
        await _localNotifications.cancel(999999);
      }
      print('Badge cleared');
    } catch (e) {
      print('Error clearing badge: $e');
    }
  }
}

