import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/screens/Authstate/auth_wrapper.dart';
import 'package:vibetalk/screens/Calling/calling_screen.dart';
import 'package:vibetalk/screens/Calling/incoming_call_screen.dart';
import 'package:vibetalk/screens/Conservation/conversation_screen.dart';
import 'package:vibetalk/models/user_model.dart';
import 'services/notification_services.dart';
import 'theme/app_theme.dart';

// ─────────────────────────────────────────────────────────
// Background FCM handler — must be a top-level function
// ─────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📬 Background message: ${message.messageId}');
  await NotificationService.initializeForBackground();
  await NotificationService.showLocalNotification(message);
}

// ─────────────────────────────────────────────────────────
// Permission helper — requests camera, mic, bluetooth,
// notifications, and system-alert-window in one shot.
// ─────────────────────────────────────────────────────────
Future<void> _requestAllPermissions() async {
  final statuses = await [
    Permission.microphone,
    Permission.camera,
    Permission.bluetoothConnect,
    Permission.notification,
    // systemAlertWindow allows drawing over other apps (needed for
    // full-screen call overlays on Android 6-13).
    Permission.systemAlertWindow,
  ].request();

  statuses.forEach((permission, status) {
    debugPrint('🔐 $permission: $status');
  });

  // Android 14+ (API 34) requires USE_FULL_SCREEN_INTENT to be granted
  // explicitly by the user for call-style full-screen notifications.
  // Without this, fullScreenIntent:true falls back to a heads-up banner.
  if (await Permission.scheduleExactAlarm.isDenied) {
    await Permission.scheduleExactAlarm.request();
  }

  // Request ignoring battery optimization so FCM wakes the app reliably
  // in killed state. On Realme/Xiaomi/OPPO this is especially important.
  final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
  if (batteryStatus.isDenied) {
    debugPrint('⚡ Requesting battery optimization exemption...');
    await Permission.ignoreBatteryOptimizations.request();
  }
}

// ─────────────────────────────────────────────────────────
// FCM token warm-up — ensures the token is cached before
// NotificationService needs it.
// ─────────────────────────────────────────────────────────
Future<void> _ensureFcmTokenReady() async {
  try {
    final token = await FirebaseMessaging.instance.getToken().timeout(
      const Duration(seconds: 10),
    );
    debugPrint('✅ FCM token ready: $token');
  } catch (e) {
    debugPrint('⚠️ FCM token not ready within 10s: $e');
  }
}

// ─────────────────────────────────────────────────────────
// main()
// Startup sequence:
//   1. Firebase init
//   2. Register background FCM handler
//   3. Request all permissions
//   4. Warm up FCM token
//   5. NotificationService init
//   6. runApp
// ─────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _requestAllPermissions();
  await NotificationService.initialize();

  // Pre-extract any pending call from a notification that launched the app
  // from killed state. Doing this BEFORE runApp prevents SplashScreen flash.
  final pendingCall = await NotificationService.extractPendingCall();

  // If the user tapped ✅ Accept on the notification, pre-fetch the CallModel
  // NOW (before runApp) so the UI can navigate instantly without an extra
  // Firestore round-trip after the first frame.
  CallModel? pendingCallModel;
  if (pendingCall?.actionId == 'accept_call') {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(pendingCall!.callId)
          .get();
      if (snap.exists && snap.data() != null) {
        final call = CallModel.fromMap(snap.data()!);
        if (call.status == 'ringing') {
          pendingCallModel = call;
          debugPrint('✅ Pre-fetched call model for instant CallingScreen');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not pre-fetch call model: $e');
    }
  }

  runApp(
    ProviderScope(
      child: MyApp(
        pendingCall: pendingCall,
        pendingCallModel: pendingCallModel,
      ),
    ),
  );

  // Warm-up FCM token in background — don't block runApp
  _ensureFcmTokenReady();
}

// ─────────────────────────────────────────────────────────
// App widget
// ─────────────────────────────────────────────────────────
class MyApp extends ConsumerStatefulWidget {
  /// Pre-extracted pending call from a notification that launched the app
  /// from killed state. Null when the app was opened normally.
  final ({String callId, String? actionId})? pendingCall;

  /// Pre-fetched CallModel for instant Accept navigation (avoids a
  /// Firestore round-trip after the first frame when Accept was tapped).
  final CallModel? pendingCallModel;

  const MyApp({super.key, this.pendingCall, this.pendingCallModel});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Deduplication: track the last handled call action to avoid processing
  // the same notification twice (FCM can deliver duplicates; the pendingCall
  // path and the callback path can both fire for the same accept_call).
  String? _lastHandledCallKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.onNotificationTap = _handleNotificationTap;
      NotificationService.onCallNotificationTap = (callId, {actionId}) =>
          _handleCallNotificationTap(callId, actionId: actionId);
      NotificationService.onCallDeclineTap = _handleCallDeclineTap;

      final pending = widget.pendingCall;
      if (pending != null) {
        // App was launched from a call notification — route immediately.
        if (pending.actionId == 'decline_call') {
          _handleCallDeclineTap(pending.callId);
        } else if (pending.actionId == 'accept_call') {
          // Suppress BEFORE any async work.
          NotificationService.suppressIncomingCallUI(pending.callId);

          final preloadedCall = widget.pendingCallModel;
          if (preloadedCall != null) {
            // Call model already fetched in main() — navigate instantly.
            final ctx = navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              Navigator.of(ctx)
                  .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CallingScreen(call: preloadedCall, isCaller: false),
                    ),
                  )
                  .then((_) => NotificationService.clearSuppressedCall());
            }
          } else {
            // Fallback: fetch from Firestore (slower path).
            _handleCallNotificationTap(
              pending.callId,
              actionId: pending.actionId,
            );
          }
        } else {
          _handleCallNotificationTap(
            pending.callId,
            actionId: pending.actionId,
          );
        }
      } else {
        // Normal launch — check for edge-case notification launches
        NotificationService.checkNotificationLaunchDetails();
        NotificationService.getInitialMessage();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 App lifecycle: $state');
  }

  // ── Chat notification tap ──────────────────────────────────────────────────
  void _handleNotificationTap(
    String chatId,
    String friendId,
    String friendUsername,
  ) {
    debugPrint('🔔 Chat notification tapped — ChatId: $chatId');

    final context = navigatorKey.currentContext;
    if (context == null) return;

    final friend = UserModel(
      uid: friendId,
      email: '',
      username: friendUsername,
      fcmToken: '',
      createdAt: DateTime.now(),
      searchKeywords: [],
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(chatId: chatId, friend: friend),
      ),
    );
  }

  // ── Call notification tap (app killed/background) ─────────────────────────
  void _handleCallNotificationTap(String callId, {String? actionId}) async {
    // Deduplicate — ignore if we already handled this exact call+action
    // within the last 5 seconds.
    final key = '$callId:$actionId';
    if (_lastHandledCallKey == key) {
      debugPrint('🔄 [CallNotif] Duplicate ignored: $key');
      return;
    }
    _lastHandledCallKey = key;
    Future.delayed(
      const Duration(seconds: 5),
      () => _lastHandledCallKey = null,
    );

    debugPrint('📞 Call notification — callId: $callId, action: $actionId');

    // Suppress BEFORE any async work so auth_wrapper's Firestore stream
    // cannot push a duplicate IncomingCallScreen while we are navigating.
    // This covers both Accept taps AND regular notification taps.
    NotificationService.suppressIncomingCallUI(callId);

    final context = navigatorKey.currentContext;
    if (context == null) {
      NotificationService.clearSuppressedCall();
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();

      if (!snap.exists || snap.data() == null) {
        debugPrint('⚠️ Call $callId no longer exists');
        NotificationService.clearSuppressedCall();
        return;
      }

      final call = CallModel.fromMap(snap.data()!);

      if (call.status != 'ringing') {
        debugPrint('⚠️ Call $callId is no longer ringing (${call.status})');
        NotificationService.clearSuppressedCall();
        return;
      }

      if (!context.mounted) {
        NotificationService.clearSuppressedCall();
        return;
      }

      if (actionId == 'accept_call') {
        // User tapped ✅ Accept on notification shade — skip IncomingCallScreen.
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => CallingScreen(call: call, isCaller: false),
              ),
            )
            .then((_) => NotificationService.clearSuppressedCall());
      } else {
        // Regular notification tap — show IncomingCallScreen.
        // Clear suppression AFTER push so auth_wrapper sees it and skips.
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => IncomingCallScreen(call: call),
              ),
            )
            .then((_) => NotificationService.clearSuppressedCall());
      }
    } catch (e) {
      NotificationService.clearSuppressedCall();
      debugPrint('❌ Failed to load call $callId: $e');
    }
  }

  // ── Decline from notification banner (app killed/background) ──────────────
  // The user tapped ❌ Decline on the notification shade.
  // We update Firestore status to 'rejected' without showing IncomingCallScreen.
  void _handleCallDeclineTap(String callId) async {
    debugPrint('📞 Call declined from notification — callId: $callId');
    try {
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'rejected',
      });
      debugPrint('✅ Call $callId marked rejected');
    } catch (e) {
      debugPrint('❌ Failed to decline call $callId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeTalk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      home: const AuthenticationWrapper(),
    );
  }
}
