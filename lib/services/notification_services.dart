import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/env_config.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static late AndroidNotificationChannel _channel;
  static bool _isInitialized = false;

  // Get backend URL from environment config
  static String get _backendUrl => EnvConfig.notificationBackendUrl;
  static String? get _apiKey => EnvConfig.notificationBackendUrl.isNotEmpty
      ? null
      : null; // Add API key to EnvConfig if needed

  // Tracks which chatId the user is currently viewing.
  // When set, foreground notifications for that chat are suppressed.
  static String? _activeChatId;

  /// Call this when the user enters a conversation screen.
  static void setActiveChatId(String chatId) {
    _activeChatId = chatId;
    debugPrint('🔕 Notifications suppressed for chat: $chatId');
  }

  /// Call this when the user leaves a conversation screen.
  static void clearActiveChatId() {
    debugPrint('🔔 Notifications re-enabled (was: $_activeChatId)');
    _activeChatId = null;
  }

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
        settings: initSettings,
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

  // Lightweight init for killed-state background isolates.
  // Skips requestPermission() which can stall when there is no Activity context.
  static Future<void> initializeForBackground() async {
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

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(settings: initSettings);
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📩 Foreground message received: ${message.data}');

    // Suppress notification if user is already viewing the chat that sent this message
    final chatId = message.data['chatId'] as String?;
    if (chatId != null && chatId == _activeChatId) {
      debugPrint('🔕 Suppressing notification — user is in chat: $chatId');
      return;
    }

    // Also suppress call-type notifications in foreground — ZEGOCLOUD handles those
    final type = message.data['type'] as String?;
    if (type == 'call') {
      debugPrint('🔕 Suppressing call notification in foreground — ZEGOCLOUD handles it');
      return;
    }

    await showLocalNotification(message);
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    // Use notification object if available, otherwise fallback to data payload
    final title =
        notification?.title ??
        data['title'] ??
        data['senderName'] ??
        'New Message';
    final body = notification?.body ?? data['body'] ?? data['message'] ?? '';

    if (!kIsWeb) {
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
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
        id: message.hashCode,
        title: title,
        body: body,
        notificationDetails: details,
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
