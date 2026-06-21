package com.anish.vibetalk

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    // Flutter calls this channel to move the app to the background after
    // a call is declined/missed while the phone was locked, so the lock
    // screen returns instead of revealing the home screen.
    private val CHANNEL = "vibetalk/window"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow the Flutter UI to be shown over the lock screen without requiring a PIN
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Keep screen on during call so it doesn't dim mid-call.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Remove the window open animation when launched from fullScreenIntent.
        // This eliminates the slide-in transition that creates a visual glitch
        // when the call notification fires on the lock screen.
        overridePendingTransition(0, 0)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Move the app to the background so the lock screen returns.
                // Called by IncomingCallScreen when the user declines/misses
                // a call that arrived while the phone was locked.
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }

                // Returns true if the keyguard (lock screen) is currently
                // locked. Flutter uses this to decide whether to call
                // moveToBackground after declining a call.
                "isLocked" -> {
                    val km = getSystemService(Context.KEYGUARD_SERVICE)
                            as KeyguardManager
                    result.success(km.isKeyguardLocked)
                }

                else -> result.notImplemented()
            }
        }
    }

    // Forward new intents to Flutter engine so call notification
    // accept/reject actions are properly delivered when the app is already
    // running in the background and gets brought to the foreground.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}

