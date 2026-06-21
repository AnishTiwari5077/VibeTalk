import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../core/env_config.dart';

// =============================================================================
// Background notification action handler (top-level, @pragma required).
//
// Called by flutter_local_notifications when the user taps an action button
// (Accept / Decline) on a local notification WHILE THE APP IS KILLED.
//
// IMPORTANT: This runs in a SEPARATE Dart isolate — it cannot access any
// static state from the running app. Firebase must be re-initialized here.
// =============================================================================
@pragma('vm:entry-point')
Future<void> onNotificationActionBackground(
  NotificationResponse response,
) async {
  // Only the Decline button has showsUserInterface:false, so this handler
  // only needs to handle decline. Accept opens the app normally.
  if (response.actionId != 'decline_call') return;

  try {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final data = jsonDecode(payload) as Map<String, dynamic>;
    final callId = data['callId'] as String?;
    if (callId == null || callId.isEmpty) return;

    // Initialize Firebase in this background isolate so we can write Firestore.
    await Firebase.initializeApp();

    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'status': 'rejected',
    });

    debugPrint('📞 [BG] Call $callId rejected from notification shade');
  } catch (e) {
    debugPrint('❌ [BG] Background decline failed: $e');
  }
}

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
  // Uses the device's default RINGTONE sound (not notification sound).
  // Channel ID is versioned — changing the sound requires a new channel ID
  // because Android locks channel settings after first creation.
  static const AndroidNotificationChannel
  _callChannel = AndroidNotificationChannel(
    'call_channel_v2',
    'Incoming Calls',
    description: 'Ringing notifications for incoming voice and video calls',
    importance: Importance.max,
    playSound: true,
    // Use the device's chosen default ringtone so it sounds like a real call.
    // RawResourceAndroidNotificationSound('ringtone') can be used instead
    // if you bundle a custom audio file at android/app/src/main/res/raw/ringtone.mp3
    sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFF00FF00),
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
  /// [actionId] will be 'accept_call' when the user tapped ✅ Accept.
  static Function(String callId, {String? actionId})? onCallNotificationTap;

  /// Set this in main.dart to silently decline a call when the user taps
  /// the "Decline" action button on the notification shade.
  static Function(String callId)? onCallDeclineTap;

  // ---------------------------------------------------------------------------
  // Incoming call suppression (prevents auth_wrapper from pushing a duplicate
  // IncomingCallScreen when main.dart already navigated to CallingScreen).
  // ---------------------------------------------------------------------------

  /// The callId currently being handled via a notification Accept tap.
  /// auth_wrapper checks this before pushing IncomingCallScreen.
  static String? _suppressedCallId;

  /// Call before navigating to CallingScreen from an Accept notification tap.
  /// Prevents auth_wrapper._listenForIncomingCalls from pushing a duplicate
  /// IncomingCallScreen over the CallingScreen we're about to show.
  static void suppressIncomingCallUI(String callId) {
    _suppressedCallId = callId;
  }

  /// Returns true if auth_wrapper should skip pushing IncomingCallScreen for
  /// this callId (because main.dart is already navigating to CallingScreen).
  static bool isIncomingCallSuppressed(String callId) {
    return _suppressedCallId == callId;
  }

  /// Clear suppression after the call screen has been shown.
  static void clearSuppressedCall() {
    _suppressedCallId = null;
  }

  /// Cancels the local call notification for [callId].
  /// Called by auth_wrapper when the Firestore stream detects the call
  /// is no longer ringing (caller cancelled before receiver answered),
  /// so the banner disappears from the notification shade automatically.
  static Future<void> cancelCallNotification(String callId) async {
    try {
      await _localNotifications.cancel(callId.hashCode);
      debugPrint('🔕 Cancelled call notification for: $callId');
    } catch (e) {
      debugPrint('⚠️ Failed to cancel call notification: $e');
    }
  }

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
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // Also create the call channel so Android registers it before
      // the first call arrives.
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_callChannel);

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
        onDidReceiveBackgroundNotificationResponse:
            onNotificationActionBackground,
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
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_callChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(initSettings);
  }

  // ---------------------------------------------------------------------------
  // Foreground / tap handlers
  // ---------------------------------------------------------------------------

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('📩 Foreground message received: ${message.data}');
    }

    final type = message.data['type'] as String?;

    // For CALL type: the incomingCallProvider Firestore stream already pushes
    // IncomingCallScreen when the app is foreground. Showing a local
    // notification here would create a duplicate the user sees simultaneously.
    if (type == 'call') {
      if (kDebugMode) {
        debugPrint(
          '📞 Foreground call — skipping notification (Firestore stream handles UI)',
        );
      }
      return;
    }

    // Caller ended the call before receiver answered.
    // Cancel the ringing notification on this device immediately.
    if (type == 'cancel_call') {
      final callId = message.data['callId'] as String? ?? '';
      if (callId.isNotEmpty) {
        await _localNotifications.cancel(callId.hashCode);
        debugPrint('🔕 Foreground: cancelled call notification for $callId');
      }
      return;
    }

    // Suppress if user is already in the chat that sent this message
    final chatId = message.data['chatId'] as String?;
    if (chatId != null && chatId == _activeChatId) {
      if (kDebugMode) {
        debugPrint('🔕 Suppressing notification — user is in chat: $chatId');
      }
      return;
    }

    await showLocalNotification(message);
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final type = data['type'] as String?;

    // Prefer notification object; fall back to data payload fields
    final title =
        notification?.title ??
        data['title'] ??
        data['senderName'] ??
        'New Message';
    final body = notification?.body ?? data['body'] ?? data['message'] ?? '';

    if (!kIsWeb) {
      NotificationDetails details;

      // Caller ended the call before receiver answered.
      // Cancel the ringing notification silently (no new banner).
      // This runs in the background isolate when a cancel_call FCM arrives.
      if (type == 'cancel_call') {
        final callId = data['callId'] as String? ?? '';
        if (callId.isNotEmpty) {
          await _localNotifications.cancel(callId.hashCode);
          debugPrint('🔕 Background: cancelled call notification for $callId');
        }
        return;
      }

      if (type == 'call') {
        // Full-screen intent pops over the lock screen (Android 10+).
        // On an unlocked screen it appears as a heads-up banner — we add
        // Accept / Decline action buttons so users can answer from the shade.
        final androidDetails = AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          // Use system ringtone — matches the channel sound
          sound: const UriAndroidNotificationSound(
            'content://settings/system/ringtone',
          ),
          enableVibration: true,
          // Repeating vibration: wait 0ms, buzz 1s, pause 0.5s, buzz 1s...
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'accept_call',
              '✅ Accept',
              showsUserInterface: true, // brings app to foreground
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'decline_call',
              '❌ Decline',
              // showsUserInterface: false — decline happens entirely in
              // onNotificationActionBackground (background isolate) without
              // opening the app. The caller sees 'rejected' via Firestore.
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
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

      // Use callId.hashCode as a stable notification ID for calls.
      // This lets cancelCallNotification() find and dismiss the exact
      // notification when the caller hangs up before the receiver answers.
      // For other types, message.hashCode is fine (each message is unique).
      final notifId = (type == 'call')
          ? (data['callId'] as String? ?? '').hashCode
          : message.hashCode;

      await _localNotifications.show(
        notifId,
        title,
        body,
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
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _processNotificationData(data, actionId: response.actionId);
      } catch (e) {
        debugPrint('❌ Error processing notification tap: $e');
        if (kDebugMode) rethrow;
      }
    }
  }

  static void _processNotificationData(
    Map<String, dynamic> data, {
    String? actionId,
  }) {
    final type = data['type'] as String?;

    switch (type) {
      case 'call':
        final callId = data['callId'] as String?;
        if (callId == null || callId.isEmpty) break;

        if (actionId == 'decline_call') {
          debugPrint('📞 Call declined from notification — callId: $callId');
          onCallDeclineTap?.call(callId);
        } else {
          // Regular tap or Accept button — pass actionId so caller can auto-accept
          debugPrint(
            '📞 Call tapped/accepted — callId: $callId, action: $actionId',
          );
          onCallNotificationTap?.call(callId, actionId: actionId);
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
      'token': receiverToken,
      'senderName': senderName,
      'senderId': senderId,
      'chatId': chatId,
      'body': messageContent,
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
      'token': receiverToken,
      'senderName': senderName,
      'senderId': senderId,
      'requestId': requestId,
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
      'token': receiverToken,
      'acceptorName': acceptorName,
      'acceptorId': acceptorId,
      'chatId': chatId,
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
      'token': receiverToken,
      'callerName': callerName,
      'callId': callId,
      'isVideo': isVideo,
      'title': callerName,
      'body': isVideo
          ? '$callerName is video calling you…'
          : '$callerName is calling you…',
    });
  }

  /// POST /send-cancel-call
  /// Sends a data-only `type: cancel_call` FCM to the receiver so their
  /// background handler cancels the ringing notification immediately,
  /// even when their app is killed (no active Firestore stream).
  static Future<bool> sendCancelCallNotification({
    required String receiverToken,
    required String callId,
  }) async {
    return _post('/send-cancel-call', {
      'token': receiverToken,
      'callId': callId,
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
      'body': body,
      'data': data ?? {},
    });
  }

  // ---------------------------------------------------------------------------
  // HTTP helper — all requests go through here
  // ---------------------------------------------------------------------------

  static Future<bool> _post(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (_backendUrl.isEmpty) {
        debugPrint(
          '❌ Backend URL not configured — set NOTIFICATION_BACKEND_URL in dart_defines.json',
        );
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
        debugPrint(
          '❌ $endpoint failed [${response.statusCode}]: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ $endpoint error: $e');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        debugPrint(
          '  → Check: backend is running, NOTIFICATION_BACKEND_URL is correct, device is on same network',
        );
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  /// Called when the app is launched from a KILLED state by tapping a
  /// local notification (background-handler-shown call notification).
  /// `onDidReceiveNotificationResponse` does NOT fire in that scenario —
  /// `getNotificationAppLaunchDetails` is the correct API.
  static Future<void> checkNotificationLaunchDetails() async {
    try {
      final details = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        final actionId = details?.notificationResponse?.actionId;
        if (payload != null && payload.isNotEmpty) {
          debugPrint('📲 App launched from local notification: $payload');
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _processNotificationData(data, actionId: actionId);
        }
      }
    } catch (e) {
      debugPrint('❌ checkNotificationLaunchDetails error: $e');
    }
  }

  /// Pre-extract the call ID from a notification that launched the app
  /// from killed state. Call this BEFORE runApp() to avoid the brief
  /// SplashScreen flash when navigating to IncomingCallScreen.
  static Future<({String callId, String? actionId})?>
  extractPendingCall() async {
    try {
      final details = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        final actionId = details?.notificationResponse?.actionId;
        if (payload != null && payload.isNotEmpty) {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          if (data['type'] == 'call') {
            final callId = data['callId'] as String?;
            if (callId != null && callId.isNotEmpty) {
              return (callId: callId, actionId: actionId);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Checks Firebase for a message that launched the app from killed state
  /// (when FCM delivers a notification+data message and the OS shows it).
  static Future<RemoteMessage?> getInitialMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message != null) {
        debugPrint('📬 Initial FCM message: ${message.data}');
        _processNotificationData(message.data);
      }
      return message;
    } catch (e) {
      debugPrint('❌ Error getting initial message: $e');
      return null;
    }
  }
}
