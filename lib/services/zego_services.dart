import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_zpns/zego_zpns.dart';
import '../core/env_config.dart';
import '../providers/call_state_provider.dart';
import '../screens/Calling/calling_screen.dart';

class ZegoService {
  static int get appID => EnvConfig.zegoAppId;
  static String get appSign => EnvConfig.zegoAppSign;

  static bool _isInitialized = false;

  static Future<void> initializeZego({
    required String userId,
    required String userName,
  }) async {
    if (appID == 0 || appSign.isEmpty) {
      throw Exception('ZEGO credentials not configured');
    }

    if (_isInitialized) return;

    // ── Guard: Zego rejects empty userId or userName with
    //   "user parameters is not valid", which silently leaves
    //   _pageManager null inside the SDK. Any subsequent send()
    //   then throws AssertionError: '_pageManager != null'.
    //   We validate here so _isInitialized is never set true
    //   with bad credentials.
    if (userId.isEmpty) {
      throw Exception('[ZegoService] userId is empty — cannot init Zego');
    }

    if (userName.isEmpty) {
      // FIX: Treat empty userName as a hard error instead of a soft warning.
      // When userName is empty, Zego's init() silently skips setting up
      // _pageManager internally. _isInitialized would then become true with
      // a broken state, causing every subsequent call attempt to throw:
      //   AssertionError: '_pageManager != null'
      // Throwing here ensures _isInitialized stays false so auth_wrapper
      // will retry init once Firestore delivers the real username.
      throw Exception(
        '[ZegoService] userName is empty — Firestore user document may not be fully loaded yet. Init aborted.',
      );
    }

    debugPrint('🔧 [ZegoService] Initializing with userId=$userId userName=$userName');

    // Step 1: Initialize the Zego call invitation service FIRST
    await ZegoUIKitPrebuiltCallInvitationService().init(
      appID: appID,
      appSign: appSign,
      userID: userId,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],

      // Wire Riverpod state to Zego call events
      invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
        onOutgoingCallSent: (callID, caller, callType, callees, customData) {
          globalCallStateController.updateState(CallState.calling);
        },
        onInvitationUserStateChanged: (userInfoList) {
          for (final user in userInfoList) {
            final stateStr = user.state.toString();
            if (stateStr.contains('received') ||
                stateStr.contains('notified')) {
              globalCallStateController.updateState(CallState.ringing);
            } else if (stateStr.contains('accepted')) {
              globalCallStateController.updateState(CallState.connected);
            } else if (stateStr.contains('rejected') ||
                stateStr.contains('cancelled')) {
              globalCallStateController.updateState(CallState.ended);
            }
          }
        },
        onOutgoingCallAccepted: (callID, callee) {
          globalCallStateController.updateState(CallState.connected);
        },
        onOutgoingCallDeclined: (callID, callee, customData) {
          globalCallStateController.updateState(CallState.rejected);
        },
        onOutgoingCallRejectedCauseBusy: (callID, callee, customData) {
          globalCallStateController.updateState(CallState.rejected);
        },
        onOutgoingCallTimeout: (callID, callees, isVideoCall) {
          globalCallStateController.updateState(CallState.timeout);
        },
        onIncomingCallReceived:
            (callID, caller, callType, callees, customData) {
              globalCallStateController.updateState(CallState.ringing);
            },
        onIncomingCallCanceled: (callID, caller, customData) {
          globalCallStateController.updateState(CallState.ended);
        },
        onIncomingCallTimeout: (callID, caller) {
          globalCallStateController.updateState(CallState.timeout);
        },
      ),

      // ─────────────────────────────────────────────────
      // FIX: pageBuilder callback type.
      // ZegoCallInvitationInviterUIConfig.pageBuilder delivers
      // a ZegoCallingBuilderInfo, not ZegoCallInvitationData.
      // Both types exist in the SDK; the wrong one causes a
      // runtime type error the first time a call is placed,
      // so the custom screen never appears and the call fails
      // silently. The parameter name is left as
      // `callInvitationData` for readability but its type is
      // now explicitly ZegoCallingBuilderInfo to match what
      // Zego actually passes into pageBuilder.
      // ─────────────────────────────────────────────────
      uiConfig: ZegoCallInvitationUIConfig(
        inviter: ZegoCallInvitationInviterUIConfig(
          pageBuilder: (context, ZegoCallingBuilderInfo callInvitationData) {
            return CallingScreen(
              callInvitationData: callInvitationData,
              isCaller: true,
            );
          },
        ),
        invitee: ZegoCallInvitationInviteeUIConfig(
          pageBuilder: (context, ZegoCallingBuilderInfo callInvitationData) {
            return CallingScreen(
              callInvitationData: callInvitationData,
              isCaller: false,
            );
          },
        ),
      ),

      notificationConfig: ZegoCallInvitationNotificationConfig(
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          showOnFullScreen: true,
          showOnLockedScreen: true,
          callChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: 'ZegoUIKit',
            channelName: 'VibeTalk Calls',
            sound: 'ringtone',
            icon: 'notification_icon',
          ),
          missedCallChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: 'ZegoUIKitMissed',
            channelName: 'VibeTalk Missed Calls',
            sound: 'ringtone',
            icon: 'notification_icon',
          ),
        ),
      ),

      requireConfig: (ZegoCallInvitationData data) {
        final bool isGroup = data.invitees.length > 1;
        final bool isVideo = data.type == ZegoCallInvitationType.videoCall;

        if (isGroup) {
          return isVideo
              ? ZegoUIKitPrebuiltCallConfig.groupVideoCall()
              : ZegoUIKitPrebuiltCallConfig.groupVoiceCall();
        } else {
          return isVideo
              ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
        }
      },
    );

    _isInitialized = true;
    debugPrint('✅ ZegoService initialized for user: $userId');

    // Step 2: Register push in background — non-blocking.
    // Push is only needed to RECEIVE offline call notifications.
    // Running it concurrently means the call button is usable
    // immediately after init() completes.
    unawaited(_registerPushInBackground());
  }

  /// Registers the device with ZEGOCLOUD's push server.
  /// Runs concurrently after init() so it never delays the first call.
  static Future<void> _registerPushInBackground() async {
    try {
      final ZPNsConfig zpnsConfig = ZPNsConfig();
      zpnsConfig.enableFCMPush = true;
      ZPNs.setPushConfig(zpnsConfig);
      ZPNs.enableDebug(true);

      ZPNsEventHandler.onRegistered = (ZPNsRegisterMessage message) {
        if (message.errorCode == 0) {
          debugPrint('✅ ZPNs registered! PushID: ${message.pushID}');
        } else {
          debugPrint('❌ ZPNs registration failed. Error: ${message.errorCode}');
        }
      };

      // Warm up the FCM token so ZPNs.registerPush() finds a cached value.
      // On first launch the token is generated async; awaiting here prevents
      // the silent errorCode != 0 that left offline call push broken.
      try {
        await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 10),
        );
        debugPrint('✅ FCM token confirmed ready for ZPNs registration');
      } catch (e) {
        debugPrint(
          '⚠️ FCM token check failed: $e — attempting registerPush anyway',
        );
      }

      await ZPNs.getInstance().registerPush(
        iOSEnvironment: ZPNsIOSEnvironment.Automatic,
      );
      debugPrint('📲 ZPNs registerPush called successfully');
    } catch (e) {
      debugPrint('❌ ZPNs registerPush error: $e');
    }
  }

  static Future<void> uninitializeZego() async {
    if (!_isInitialized) return;
    await ZegoUIKitPrebuiltCallInvitationService().uninit();
    _isInitialized = false;
    debugPrint('🔌 ZegoService uninitialized');
  }

  static bool get isInitialized => _isInitialized;
}
