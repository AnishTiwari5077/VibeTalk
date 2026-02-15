import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/env_config.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static late AndroidNotificationChannel _channel;
  static bool _isInitialized = false;

  // Get backend URL from environment config
  static String get _backendUrl => EnvConfig.notificationBackendUrl;
  static String? get _apiKey => EnvConfig.notificationBackendUrl.isNotEmpty
      ? null
      : null; // Add API key to EnvConfig if needed

  // Callback for navigation when notification is tapped
  static Function(String chatId, String friendId, String friendUsername)?
  onNotificationTap;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('❌ Notification permission denied');
        return;
      }

      _channel = const AndroidNotificationChannel(
        'chat_channel',
        'Chat Notifications',
        description: 'Notifications for chat messages',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      _messaging.onTokenRefresh.listen(_handleTokenRefresh);

      _isInitialized = true;
      debugPrint('✅ NotificationService initialized');
      debugPrint('📍 Backend URL: $_backendUrl');
    } catch (e) {
      debugPrint('❌ NotificationService initialization failed: $e');
      if (kDebugMode) {
        rethrow;
      }
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📩 Foreground message: ${message.notification?.title}');
    await _showLocalNotification(message);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;

    if (notification != null && !kIsWeb) {
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          notification.body ?? '',
          contentTitle: notification.title,
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        notification.hashCode,
        notification.title ?? 'New Message',
        notification.body ?? '',
        details,
        payload: jsonEncode(message.data),
      );
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint('🔔 Notification tapped: ${message.data}');
    _processNotificationData(message.data);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _processNotificationData(data);
      } catch (e) {
        debugPrint('❌ Error processing notification tap: $e');
        if (kDebugMode) {
          rethrow;
        }
      }
    }
  }

  static void _processNotificationData(Map<String, dynamic> data) {
    final type = data['type'];

    switch (type) {
      case 'message':
        final chatId = data['chatId'] as String?;
        final senderId = data['senderId'] as String?;
        final senderName = data['senderName'] as String?;

        if (chatId != null && senderId != null && senderName != null) {
          debugPrint('📱 Navigating to chat: $chatId');
          onNotificationTap?.call(chatId, senderId, senderName);
        }
        break;
      case 'friend_request':
        debugPrint('👥 Friend request notification');
        break;
      case 'request_accepted':
        debugPrint('✅ Friend request accepted notification');
        break;
      default:
        debugPrint('❓ Unknown notification type: $type');
        break;
    }
  }

  static Future<void> _handleTokenRefresh(String token) async {
    debugPrint('🔄 Token refreshed: $token');
    // Token will be updated when user logs in through auth_repository
  }

  static Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token: ${token.substring(0, 20)}...');
      }
      return token;
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  static Future<void> updateTokenInFirestore(
    String userId,
    String token,
  ) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Token updated in Firestore for user: $userId');
    } catch (e) {
      debugPrint('❌ Error updating token in Firestore: $e');
    }
  }

  static Future<bool> sendMessageNotification({
    required String receiverToken,
    required String senderName,
    required String messageContent,
    required String chatId,
    required String senderId,
  }) async {
    try {
      if (_backendUrl.isEmpty) {
        debugPrint('❌ Backend URL not configured in .env');
        debugPrint('   Please add NOTIFICATION_BACKEND_URL to your .env file');
        return false;
      }

      debugPrint('📤 Sending notification to backend: $_backendUrl');

      final headers = <String, String>{'Content-Type': 'application/json'};

      if (_apiKey != null && _apiKey!.isNotEmpty) {
        headers['x-api-key'] = _apiKey!;
      }

      final payload = {
        'token': receiverToken,
        'title': senderName,
        'body': messageContent,
        'data': {
          'type': 'message',
          'chatId': chatId,
          'senderId': senderId,
          'senderName': senderName,
        },
      };

      final response = await http
          .post(
            Uri.parse('$_backendUrl/send-notification'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ Notification sent successfully');
        debugPrint('   Response: ${response.body}');
        return true;
      } else {
        debugPrint('❌ Notification failed with status: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        debugPrint('   💡 Check that:');
        debugPrint('   1. Backend server is running (node server.js)');
        debugPrint('   2. Backend URL in .env is correct: $_backendUrl');
        debugPrint('   3. Device can reach the server (same network)');
      }
      return false;
    }
  }

  static Future<bool> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      if (_backendUrl.isEmpty) {
        debugPrint('❌ Backend URL not configured');
        return false;
      }

      final headers = <String, String>{'Content-Type': 'application/json'};

      if (_apiKey != null && _apiKey!.isNotEmpty) {
        headers['x-api-key'] = _apiKey!;
      }

      final payload = {
        'token': token,
        'title': title,
        'body': body,
        'data': data ?? {},
      };

      final response = await http
          .post(
            Uri.parse('$_backendUrl/send-notification'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      return false;
    }
  }

  static Future<Map<String, int>> sendBatchNotifications({
    required List<Map<String, dynamic>> notifications,
  }) async {
    try {
      if (_backendUrl.isEmpty) {
        return {'successCount': 0, 'failureCount': notifications.length};
      }

      final headers = <String, String>{'Content-Type': 'application/json'};

      if (_apiKey != null && _apiKey!.isNotEmpty) {
        headers['x-api-key'] = _apiKey!;
      }

      final payload = {'notifications': notifications};

      final response = await http
          .post(
            Uri.parse('$_backendUrl/send-notifications-batch'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return {
          'successCount': result['successCount'],
          'failureCount': result['failureCount'],
        };
      } else {
        return {'successCount': 0, 'failureCount': notifications.length};
      }
    } catch (e) {
      debugPrint('❌ Batch notification error: $e');
      return {'successCount': 0, 'failureCount': notifications.length};
    }
  }

  static Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      debugPrint('✅ FCM token deleted');
    } catch (e) {
      debugPrint('❌ Error deleting token: $e');
      if (kDebugMode) {
        rethrow;
      }
    }
  }

  static Future<RemoteMessage?> getInitialMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message != null) {
        debugPrint('📬 Initial message: ${message.data}');
        _processNotificationData(message.data);
      }
      return message;
    } catch (e) {
      debugPrint('❌ Error getting initial message: $e');
      return null;
    }
  }
}
