import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:new_chart/screens/Authstate/auth_wrapper.dart';
import 'package:new_chart/screens/Conservation/conversation_screen.dart';

import 'package:new_chart/models/user_model.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'services/notification_services.dart';
import 'theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ignore ZegoCloud offline push messages as they are handled automatically by Zego
  // This must be done BEFORE Firebase/dotenv initialization to prevent the 20 sec delay
  if (message.data.containsKey('zego') ||
      message.data['resourceID'] == 'zego_call' ||
      message.data.containsKey('callID')) {
    debugPrint("📬 Ignoring Zego message in custom background handler.");
    return;
  }

  await Future.wait([dotenv.load(fileName: ".env"), Firebase.initializeApp()]);
  debugPrint("📬 Background message: ${message.messageId}");


  // Show local notification for regular messages
  await NotificationService.initializeForBackground();
  await NotificationService.showLocalNotification(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([dotenv.load(fileName: ".env"), Firebase.initializeApp()]);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();

  // ⭐ Enable background calls
  ZegoUIKitPrebuiltCallInvitationService().useSystemCallingUI([
    ZegoUIKitSignalingPlugin(),
  ]);

  runApp(const ProviderScope(child: MyApp()));
}

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

    // ⭐ Add lifecycle observer for background handling
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

      // Set up notification tap handler
      NotificationService.onNotificationTap = _handleNotificationTap;
      NotificationService.getInitialMessage();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ⭐ Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('📱 App state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('✅ App resumed - calls active');
        break;
      case AppLifecycleState.paused:
        debugPrint('⏸️ App paused - calls still work in background');
        break;
      case AppLifecycleState.inactive:
        debugPrint('💤 App inactive');
        break;
      case AppLifecycleState.detached:
        debugPrint('🔌 App detached');
        break;
      case AppLifecycleState.hidden:
        debugPrint('👻 App hidden');
        break;
    }
  }

  void _handleNotificationTap(
    String chatId,
    String friendId,
    String friendUsername,
  ) {
    debugPrint('🔔 Notification tapped - ChatId: $chatId');

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
        builder: (context) =>
            ConversationScreen(chatId: chatId, friend: friend),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Professional Chat",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            // ⭐ This overlay handles calls in foreground and background
            ZegoUIKitPrebuiltCallMiniOverlayPage(
              contextQuery: () => navigatorKey.currentState!.context,
            ),
          ],
        );
      },
      home: const AuthenticationWrapper(),
    );
  }
}
