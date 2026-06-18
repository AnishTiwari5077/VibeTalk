import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/screens/Authstate/auth_wrapper.dart';
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
    Permission.systemAlertWindow,
  ].request();

  statuses.forEach((permission, status) {
    debugPrint('🔐 $permission: $status');
  });
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
  await _ensureFcmTokenReady();
  await NotificationService.initialize();

  runApp(const ProviderScope(child: MyApp()));
}

// ─────────────────────────────────────────────────────────
// App widget
// ─────────────────────────────────────────────────────────
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.onNotificationTap = _handleNotificationTap;
      NotificationService.onCallNotificationTap = _handleCallNotificationTap;
      NotificationService.getInitialMessage();
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
  void _handleCallNotificationTap(String callId) async {
    debugPrint('📞 Call notification tapped — callId: $callId');

    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      // Fetch the call document from Firestore
      final snap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();

      if (!snap.exists || snap.data() == null) {
        debugPrint('⚠️ Call $callId no longer exists');
        return;
      }

      final call = CallModel.fromMap(snap.data()!);

      // Only navigate if the call is still ringing
      if (call.status != 'ringing') {
        debugPrint('⚠️ Call $callId is no longer ringing (${call.status})');
        return;
      }

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(call: call),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to load call $callId: $e');
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
