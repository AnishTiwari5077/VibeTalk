import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'core/env_config.dart';

class FirebaseEnvOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: EnvConfig.firebaseAndroidApiKey,
    appId: EnvConfig.firebaseAndroidAppId,
    messagingSenderId: EnvConfig.firebaseSenderId,
    projectId: EnvConfig.firebaseProjectId,
    databaseURL: EnvConfig.firebaseDatabaseUrl.isNotEmpty
        ? EnvConfig.firebaseDatabaseUrl
        : null,
    storageBucket: EnvConfig.firebaseStorageBucket.isNotEmpty
        ? EnvConfig.firebaseStorageBucket
        : null,
  );

  // iOS keys are injected via --dart-define at build time just like Android.
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: _iosApiKey,
    appId: _iosAppId,
    messagingSenderId: EnvConfig.firebaseSenderId,
    projectId: EnvConfig.firebaseProjectId,
    databaseURL: EnvConfig.firebaseDatabaseUrl.isNotEmpty
        ? EnvConfig.firebaseDatabaseUrl
        : null,
    storageBucket: EnvConfig.firebaseStorageBucket.isNotEmpty
        ? EnvConfig.firebaseStorageBucket
        : null,
    iosBundleId: _iosBundleId.isNotEmpty ? _iosBundleId : null,
  );
}
