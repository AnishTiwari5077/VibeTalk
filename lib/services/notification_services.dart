import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/env_config.dart';

// =============================================================================
// NotificationService
//
// All push notifications are sent through the Node.js FCM backend
// (node_js/fcm-backend/fcm-backend/server.js).
//
// Endpoints used:
//   POST /send-message          – chat messages
//   POST /send-friend-request   – new friend requests
//   POST /send-request-accepted – accepted friend requests
//   POST /send-unfriend         – unfriend events
//   POST /send-call             – voice/video call (data-only, WebRTC wake)
//   POST /send-notification     – generic fallback
// =============================================================================
class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'chat_channel',
    'Chat Notifications',
    description: 'Notifications for chat messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // Dedicated high-priority channel for incoming calls.
  // fullScreenIntent requires this channel to have Importance.max.
  static const AndroidNotificationChannel _callChannel =
      AndroidNotificationChannel(
    'call_channel',
    'Incoming Calls',
    description: 'Ringing notifications for incoming voice and video calls',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static bool _isInitialized = false;

  /// Base URL of the running Node.js backend, e.g. http://192.168.1.x:3000
  static String get _backendUrl => EnvConfig.notificationBackendUrl;

  // ---------------------------------------------------------------------------
  // Active-chat suppression
  // ---------------------------------------------------------------------------

  /// Tracks which chatId the user is currently viewing.
  /// When set, foreground notifications for that chat are suppressed.
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

  // ---------------------------------------------------------------------------
  // Navigation callback
  // ---------------------------------------------------------------------------

  /// Set this in main.dart to navigate when a chat notification is tapped.
  static Function(String chatId, String friendId, String friendUsername)?
      onNotificationTap;

  /// Set this in main.dart to open IncomingCallScreen when a call notification
  /// is tapped while the app is in background or killed state.
  static Function(String callId)? onCallNotificationTap;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final NotificationSettings settings = await _messaging.requestPermission(
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

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Also create the call channel so Android registers it before
      // the first call arrives.
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_callChannel);

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
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
      debugPrint('📍 Node.js backend: $_backendUrl');
    } catch (e) {
      debugPrint('❌ NotificationService initialization failed: $e');
      if (kDebugMode) rethrow;
    }
  }

  /// Lightweight init for killed-state background isolates.
  /// Skips requestPermission() which can stall when there is no Activity.
  static Future<void> initializeForBackground() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(settings: initSettings);
  }

  // ---------------------------------------------------------------------------
  // Foreground / tap handlers
  // ---------------------------------------------------------------------------

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📩 Foreground message received: ${message.data}');

    final type = message.data['type'] as String?;

    // Suppress if user is already in the chat that sent this message
    final chatId = message.data['chatId'] as String?;
    if (chatId != null && chatId == _activeChatId) {
      debugPrint('🔕 Suppressing notification — user is in chat: $chatId');
      return;
    }

    // For call-type notifications: show them so the callee can open
    // IncomingCallScreen. The incomingCallProvider handles foreground
    // via Firestore streaming; FCM is mainly for background/killed states.
    if (type == 'call') {
      debugPrint('📞 Call notification — showing for background wake');
    }

    await showLocalNotification(message);
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final type = data['type'] as String?;

    // Prefer notification object; fall back to data payload fields
    final title = notification?.title ??
        data['title'] ??
        data['senderName'] ??
        'New Message';
    final body =
        notification?.body ?? data['body'] ?? data['message'] ?? '';

    if (!kIsWeb) {
      NotificationDetails details;

      if (type == 'call') {
        // Full-screen intent makes this behave like a system call screen
        // on Android 10+ (requires USE_FULL_SCREEN_INTENT permission).
        final androidDetails = AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        );
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
        details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      } else {
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
        details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      }

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
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _processNotificationData(data);
      } catch (e) {
        debugPrint('❌ Error processing notification tap: $e');
        if (kDebugMode) rethrow;
      }
    }
  }

  static void _processNotificationData(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'call':
        // App was killed/background — user tapped the call notification.
        // Open IncomingCallScreen for the given callId.
        final callId = data['callId'] as String?;
        if (callId != null && callId.isNotEmpty) {
          debugPrint('📞 Call notification tapped — callId: $callId');
          onCallNotificationTap?.call(callId);
        }
        break;
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
        debugPrint('👥 Friend request notification tapped');
        break;
      case 'request_accepted':
        debugPrint('✅ Friend request accepted notification tapped');
        break;
      default:
        debugPrint('❓ Unknown notification type: $type');
    }
  }

  static Future<void> _handleTokenRefresh(String newToken) async {
    debugPrint('🔄 FCM token refreshed — updating Firestore');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({'fcmToken': newToken});
        debugPrint('✅ FCM token updated for: ${currentUser.uid}');
      }
    } catch (e) {
      debugPrint('❌ Failed to update FCM token: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // NODE.JS BACKEND SENDERS
  // All methods below POST to the Node.js server which uses Firebase Admin SDK
  // to send FCM messages — no direct FCM HTTP calls from Flutter.
  // ---------------------------------------------------------------------------

  /// POST /send-message
  /// Sends a chat message push notification via the Node.js backend.
  static Future<bool> sendMessageNotification({
    required String receiverToken,
    required String senderName,
    required String messageContent,
    required String chatId,
    required String senderId,
  }) async {
    return _post('/send-message', {
      'token'     : receiverToken,
      'senderName': senderName,
      'senderId'  : senderId,
      'chatId'    : chatId,
      'body'      : messageContent,
    });
  }

  /// POST /send-friend-request
  /// Sends a friend-request push notification via the Node.js backend.
  static Future<bool> sendFriendRequestNotification({
    required String receiverToken,
    required String senderName,
    required String senderId,
    required String requestId,
  }) async {
    return _post('/send-friend-request', {
      'token'     : receiverToken,
      'senderName': senderName,
      'senderId'  : senderId,
      'requestId' : requestId,
    });
  }

  /// POST /send-request-accepted
  /// Notifies a user that their friend request was accepted.
  static Future<bool> sendRequestAcceptedNotification({
    required String receiverToken,
    required String acceptorName,
    required String acceptorId,
    required String chatId,
  }) async {
    return _post('/send-request-accepted', {
      'token'       : receiverToken,
      'acceptorName': acceptorName,
      'acceptorId'  : acceptorId,
      'chatId'      : chatId,
    });
  }

  /// POST /send-call
  /// Sends a call push notification to wake the callee's device.
  static Future<bool> sendCallNotification({
    required String receiverToken,
    required String callerName,
    required String callId,
    required bool isVideo,
  }) async {
    return _post('/send-call', {
      'token'     : receiverToken,
      'callerName': callerName,
      'callId'    : callId,
      'isVideo'   : isVideo,
      'title'     : callerName,
      'body'      : isVideo
          ? '$callerName is video calling you…'
          : '$callerName is calling you…',
    });
  }

  /// POST /send-notification  (generic fallback — backward compatible)
  static Future<bool> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    return _post('/send-notification', {
      'token': token,
      'title': title,
      'body' : body,
      'data' : data ?? {},
    });
  }

  // ---------------------------------------------------------------------------
  // HTTP helper — all requests go through here
  // ---------------------------------------------------------------------------

  static Future<bool> _post(String endpoint, Map<String, dynamic> payload) async {
    try {
      if (_backendUrl.isEmpty) {
        debugPrint(
            '❌ Backend URL not configured — set NOTIFICATION_BACKEND_URL in dart_defines.json');
        return false;
      }

      final url = Uri.parse('$_backendUrl$endpoint');
      debugPrint('📤 POST $url');

      final response = await http
          .post(
            url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ $endpoint succeeded: ${response.body}');
        return true;
      } else {
        debugPrint('❌ $endpoint failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ $endpoint error: $e');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        debugPrint(
            '  → Check: backend is running, NOTIFICATION_BACKEND_URL is correct, device is on same network');
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

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
