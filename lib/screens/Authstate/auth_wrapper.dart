// lib/screens/Authstate/auth_wrapper.dart
//
// Handles auth state routing and listens for incoming WebRTC calls
// while the app is in the foreground.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/providers/call_provider.dart';
import 'package:vibetalk/providers/chart_provider.dart';
import 'package:vibetalk/providers/friend_req_provider.dart';
import 'package:vibetalk/providers/user_provider.dart';
import 'package:vibetalk/screens/Authstate/error_screen.dart';
import 'package:vibetalk/screens/Calling/incoming_call_screen.dart';
import 'package:vibetalk/screens/home_screen.dart';
import 'package:vibetalk/screens/sign_screen.dart';
import 'package:vibetalk/screens/splash_screen.dart';
import 'package:vibetalk/services/notification_services.dart';

class AuthenticationWrapper extends ConsumerStatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  ConsumerState<AuthenticationWrapper> createState() =>
      _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends ConsumerState<AuthenticationWrapper> {
  String? _previousUserId;
  DateTime? _userLoadStartTime;

  // Track the callId we already navigated to so we don't push it twice
  String? _shownCallId;

  @override
  void initState() {
    super.initState();
    // Listen for incoming calls once the widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForIncomingCalls();
    });
  }

  /// Watches the incomingCallProvider and opens IncomingCallScreen
  /// whenever a new ringing call arrives for the current user.
  void _listenForIncomingCalls() {
    ref.listenManual<AsyncValue<CallModel?>>(incomingCallProvider, (_, next) {
      final call = next.asData?.value;
      if (call == null) return;
      if (call.callId == _shownCallId) return; // already showing

      // main.dart navigated directly to CallingScreen via notification Accept.
      // Don't push IncomingCallScreen on top — mark as shown and skip.
      if (NotificationService.isIncomingCallSuppressed(call.callId)) {
        _shownCallId = call.callId;
        NotificationService.clearSuppressedCall();
        return;
      }

      _shownCallId = call.callId;

      final ctx = context;
      if (!ctx.mounted) return;

      Navigator.of(ctx)
          .push(
            MaterialPageRoute(builder: (_) => IncomingCallScreen(call: call)),
          )
          .then((_) {
            // Reset so a new call can be shown after this one ends
            _shownCallId = null;
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (firebaseUser) {
        if (firebaseUser != null) {
          final currentUserId = firebaseUser.uid;

          if (_previousUserId != null && _previousUserId != currentUserId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.invalidate(currentUserProvider);
              ref.invalidate(chatListProvider);
              ref.invalidate(allUsersProvider);
              ref.invalidate(receivedRequestsProvider);
              ref.invalidate(sentRequestsProvider);
            });
          }

          _previousUserId = currentUserId;
          _userLoadStartTime ??= DateTime.now();

          final userAsync = ref.watch(currentUserProvider);

          return userAsync.when(
            data: (currentUser) {
              if (currentUser == null) {
                final loadDuration = DateTime.now().difference(
                  _userLoadStartTime!,
                );

                if (loadDuration.inSeconds > 5) {
                  debugPrint(
                    '⚠️ User document not found after ${loadDuration.inSeconds}s - signing out',
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    await ref.read(authRepositoryProvider).signOut();
                    _userLoadStartTime = null;
                  });

                  return ErrorScreen(
                    error:
                        'Your profile data is missing.\nPlease sign in again or create a new account.',
                    onRetry: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      ref.invalidate(authStateProvider);
                    },
                  );
                }

                debugPrint(
                  '⏳ Waiting for user document... ${loadDuration.inSeconds}s',
                );
                return const SplashScreen(message: 'Loading your profile...');
              }

              _userLoadStartTime = null;
              return const HomeScreen();
            },
            loading: () {
              _userLoadStartTime ??= DateTime.now();
              return const SplashScreen(message: 'Loading profile...');
            },
            error: (e, _) {
              debugPrint('❌ Firestore error: $e');
              _userLoadStartTime = null;
              return ErrorScreen(
                error: 'Failed to load profile\n${e.toString()}',
                onRetry: () => ref.invalidate(currentUserProvider),
              );
            },
          );
        }

        // User signed out — invalidate providers
        if (_previousUserId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.invalidate(currentUserProvider);
            ref.invalidate(chatListProvider);
            ref.invalidate(allUsersProvider);
            ref.invalidate(receivedRequestsProvider);
            ref.invalidate(sentRequestsProvider);
          });
          _previousUserId = null;
          _shownCallId = null;
        }

        _userLoadStartTime = null;
        return const SignInScreen();
      },

      loading: () => const SplashScreen(message: 'Initializing...'),

      error: (e, _) => ErrorScreen(
        error: e.toString(),
        onRetry: () => ref.invalidate(authStateProvider),
      ),
    );
  }
}
