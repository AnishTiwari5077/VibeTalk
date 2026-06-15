import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/providers/chart_provider.dart';
import 'package:vibetalk/providers/friend_req_provider.dart';
import 'package:vibetalk/providers/user_provider.dart';
import 'package:vibetalk/screens/Authstate/error_screen.dart';
import 'package:vibetalk/screens/home_screen.dart';
import 'package:vibetalk/screens/sign_screen.dart';
import 'package:vibetalk/screens/splash_screen.dart';
import 'package:vibetalk/services/zego_services.dart';

class AuthenticationWrapper extends ConsumerStatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  ConsumerState<AuthenticationWrapper> createState() =>
      _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends ConsumerState<AuthenticationWrapper> {
  String? _previousUserId;
  DateTime? _userLoadStartTime;

  /// True while we are waiting for Zego to finish initializing.
  bool _zegoInitializing = false;

  /// True after Zego is initialized AND we have confirmed there is NO active
  /// call that Zego's own navigator needs to handle. Only when this is true
  /// do we allow HomeScreen to render — preventing the flash.
  bool _readyToShowHome = false;

  @override
  void initState() {
    super.initState();
  }

  /// Initializes Zego and then decides whether to go straight to HomeScreen
  /// or to hold on SplashScreen so Zego can push the call UI itself.
  Future<void> _initZegoAndDecide({
    required String userId,
    required String userName,
  }) async {
    if (_zegoInitializing) return; // guard against duplicate calls
    if (!mounted) return;

    setState(() => _zegoInitializing = true);

    try {
      await ZegoService.initializeZego(
        userId: userId,
        userName: userName,
      );
    } catch (e) {
      debugPrint('❌ ZegoService.initializeZego error: $e');
    }

    if (!mounted) return;

    // Give Zego one frame to fire its internal "offline call accepted" route
    // push before we decide whether to show HomeScreen. This replaces the
    // arbitrary 1-second delay with a deterministic check.
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // Check if Zego currently has an active call (accepted from killed/bg state).
    // If it does, Zego's own navigator is already pushing the call screen;
    // we must NOT render HomeScreen or it will appear behind/before the call UI.
    final bool hasActiveCall = _zegoHasActiveCall();

    debugPrint(
      '📞 Zego init done. Has active call: $hasActiveCall',
    );

    if (!hasActiveCall) {
      // Safe to show HomeScreen — no in-progress call.
      setState(() {
        _zegoInitializing = false;
        _readyToShowHome = true;
      });
    } else {
      // There IS an active call — stay on SplashScreen.
      // Zego's navigator will push the call screen on top of whatever is
      // showing. We poll briefly until the call ends, then show HomeScreen.
      setState(() => _zegoInitializing = false);
      _waitForCallToEndThenShowHome();
    }
  }

  /// Returns true if Zego currently has an active/connected call session.
  /// Uses the officially exposed API on ZegoUIKitPrebuiltCallInvitationService:
  ///   - isInCalling : invitation/ringing phase is active
  ///   - isInCall    : call room is connected (active call)
  bool _zegoHasActiveCall() {
    try {
      final service = ZegoUIKitPrebuiltCallInvitationService();
      return service.isInCalling || service.isInCall;
    } catch (_) {
      return false;
    }
  }

  /// Polls every 500 ms until the active call ends, then shows HomeScreen.
  void _waitForCallToEndThenShowHome() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      final stillInCall = _zegoHasActiveCall();
      if (!stillInCall) {
        if (mounted) setState(() => _readyToShowHome = true);
        return false; // stop polling
      }
      return true; // keep polling
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
                    " User document not found after ${loadDuration.inSeconds}s - signing out",
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
                  " Waiting for user document... ${loadDuration.inSeconds}s",
                );
                return const SplashScreen(message: 'Loading your profile...');
              }

              _userLoadStartTime = null;

              // ── Zego not yet initialized ──────────────────────────────────
              if (!ZegoService.isInitialized) {
                // Kick off async init (guarded against duplicate calls).
                if (!_zegoInitializing) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _initZegoAndDecide(
                      userId: currentUser.uid,
                      userName: currentUser.username,
                    );
                  });
                }
                return const SplashScreen(message: 'Connecting...');
              }

              // ── Zego initialized but we are still deciding ───────────────
              if (!_readyToShowHome) {
                return const SplashScreen(message: 'Connecting...');
              }

              // ── All good — show HomeScreen ─────────────────────────────
              return const HomeScreen();
            },
            loading: () {
              _userLoadStartTime ??= DateTime.now();
              return const SplashScreen(message: 'Loading profile...');
            },
            error: (e, _) {
              debugPrint(" Firestore error: $e");
              _userLoadStartTime = null;

              return ErrorScreen(
                error: 'Failed to load profile\n${e.toString()}',
                onRetry: () => ref.invalidate(currentUserProvider),
              );
            },
          );
        }

        if (_previousUserId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            ref.invalidate(currentUserProvider);
            ref.invalidate(chatListProvider);
            ref.invalidate(allUsersProvider);
            ref.invalidate(receivedRequestsProvider);
            ref.invalidate(sentRequestsProvider);
            await ZegoService.uninitializeZego();
          });

          _previousUserId = null;
          // Reset Zego flags on sign-out so next sign-in goes through init again.
          _zegoInitializing = false;
          _readyToShowHome = false;
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
