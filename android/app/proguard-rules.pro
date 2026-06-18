# ============================================================
# Flutter Core
# ============================================================
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# ============================================================
# WebRTC (flutter_webrtc plugin)
# R8 strips these in release — call buttons become dead taps.
# ============================================================
-keep class org.webrtc.** { *; }
-keepclassmembers class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.** { *; }
-keepclassmembers class com.cloudwebrtc.** { *; }
-dontwarn com.cloudwebrtc.**
# Keep JNI-loaded native symbols used by libwebrtc
-keepclasseswithmembernames class * {
    native <methods>;
}

# ============================================================
# ZEGOCLOUD / ZegoUIKit
# ============================================================
-keep class im.zego.** { *; }
-keep class com.zegocloud.** { *; }
-dontwarn im.zego.**
-dontwarn com.zegocloud.**

# ============================================================
# Firebase
# ============================================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }

# ============================================================
# Flutter Local Notifications
# ============================================================
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ============================================================
# Cloudinary
# ============================================================
-keep class com.cloudinary.** { *; }
-dontwarn com.cloudinary.**

# ============================================================
# OkHttp / Retrofit (used by many plugins)
# ============================================================
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ============================================================
# Gson (used by Firebase and others)
# ============================================================
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**

# ============================================================
# Kotlin
# ============================================================
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ============================================================
# Keep app classes
# ============================================================
-keep class com.anish.vibetalk.** { *; }
-keep class com.example.new_chart.** { *; }

# ============================================================
# Multidex
# ============================================================
-keep class androidx.multidex.** { *; }

# ============================================================
# General Android / AndroidX
# ============================================================
-keep class androidx.** { *; }
-dontwarn androidx.**
-keep class android.** { *; }

# ============================================================
# Prevent stripping of entry-point annotated methods
# (needed for @pragma('vm:entry-point') in Dart)
# ============================================================
-keepattributes InnerClasses
-keepattributes EnclosingMethod
