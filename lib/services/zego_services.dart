import 'package:flutter/foundation.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:zego_zpns/zego_zpns.dart';
import '../core/env_config.dart';

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
      notificationConfig: ZegoCallInvitationNotificationConfig(
        androidNotificationConfig: ZegoCallAndroidNotificationConfig(
          showOnFullScreen: true,
          showOnLockedScreen: true,
          callChannel: ZegoCallAndroidNotificationChannelConfig(
            channelID: "ZegoUIKit",
            channelName: "Call Notifications",
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
