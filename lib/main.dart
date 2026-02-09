import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:new_chart/screens/Authstate/auth_wrapper.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'services/notification_services.dart';
import 'theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run heavy initialization tasks in parallel
  await Future.wait([dotenv.load(fileName: ".env"), Firebase.initializeApp()]);

  // Set background handler after Firebase is initialized
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service
  await NotificationService.initialize();

  // Configure Zego calling UI
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

class _MyAppState extends ConsumerState<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Defer Zego navigator setup to avoid blocking the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
    });
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
