/// All secrets are injected at compile-time via --dart-define (or
/// --dart-define-from-file dart_defines.json). They are never stored on-disk
/// inside the APK. See dart_defines.json.example for the required keys.
class EnvConfig {
  // Cloudinary
  static const cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );
  static const cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
  );

  // ZEGO
  static const zegoAppId = int.fromEnvironment('ZEGO_APP_ID');
  static const zegoAppSign = String.fromEnvironment('ZEGO_APP_SIGN');

  // Notifications
  static const notificationBackendUrl = String.fromEnvironment(
    'NOTIFICATION_BACKEND_URL',
  );

  // Firebase (Android)
  static const firebaseAndroidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const firebaseAndroidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );

  // Firebase (Shared)
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseDatabaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get isConfigured {
    return cloudinaryCloudName.isNotEmpty &&
        zegoAppId != 0 &&
        firebaseProjectId.isNotEmpty;
  }
}
