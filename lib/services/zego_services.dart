import 'package:flutter/foundation.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_zpns/zego_zpns.dart';
import 'package:permission_handler/permission_handler.dart';
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

    // Request permissions BEFORE initializing Zego
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.systemAlertWindow.isDenied) {
      await Permission.systemAlertWindow.request();
    }

    // Step 1: Configure ZPNs to use FCM as the push channel
    ZPNsConfig zpnsConfig = ZPNsConfig();
    zpnsConfig.enableFCMPush = true;
    ZPNs.setPushConfig(zpnsConfig);
    ZPNs.enableDebug(true);

    // Step 2: Listen for registration result
    ZPNsEventHandler.onRegistered = (ZPNsRegisterMessage message) {
      if (message.errorCode == 0) {
        debugPrint('✅ ZPNs registered! PushID: ${message.pushID}');
      } else {
        debugPrint(
          '❌ ZPNs registration failed. Error code: ${message.errorCode}',
        );
      }
    };

    // Step 3: Register device token with ZEGOCLOUD's push server
    // This is REQUIRED — without it ZEGOCLOUD cannot send offline push to this device
    try {
      await ZPNs.getInstance().registerPush(
        iOSEnvironment: ZPNsIOSEnvironment.Automatic,
      );
      debugPrint('📲 ZPNs registerPush called successfully');
    } catch (e) {
      debugPrint('❌ ZPNs registerPush error: $e');
    }

    // Step 4: Initialize the Zego call invitation service
    await ZegoUIKitPrebuiltCallInvitationService().init(
      appID: appID,
      appSign: appSign,
      userID: userId,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],

      // Wire up Riverpod state with Zego events
      invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
        onOutgoingCallSent: (callID, caller, callType, callees, customData) {
          globalCallStateController.updateState(CallState.calling);
        },
        onInvitationUserStateChanged: (userInfoList) {
          for (var user in userInfoList) {
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

      // Inject the custom Riverpod Calling UI
      uiConfig: ZegoCallInvitationUIConfig(
        inviter: ZegoCallInvitationInviterUIConfig(
          pageBuilder: (context, callInvitationData) {
            return CallingScreen(
              callInvitationData: callInvitationData,
              isCaller: true,
            );
          },
        ),
        invitee: ZegoCallInvitationInviteeUIConfig(
          pageBuilder: (context, callInvitationData) {
            return CallingScreen(
              callInvitationData: callInvitationData,
              isCaller: false,
            );
          },
        ),
      ),
      notificationConfig: ZegoCallInvitationNotificationConfig(
        // ⭐ resourceID MUST match what is configured in ZEGOCLOUD console.
        // This tells ZEGOCLOUD to use the high-priority offline push channel
        // (FCM data-only message with priority=high) instead of the low-priority
        // normal channel — fixing the 10-20 second delivery delay.
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          showOnFullScreen: true,
          showOnLockedScreen: true,
          callChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: "ZegoUIKit",
            channelName: "VibeTalk Calls",
            sound: "ringtone",
            icon: "notification_icon",
          ),
          missedCallChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: "ZegoUIKitMissed",
            channelName: "VibeTalk Missed Calls",
            sound: "ringtone",
            icon: "notification_icon",
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
  }

  static Future<void> uninitializeZego() async {
    if (!_isInitialized) return;
    await ZegoUIKitPrebuiltCallInvitationService().uninit();
    _isInitialized = false;
  }

  static bool get isInitialized => _isInitialized;
}
