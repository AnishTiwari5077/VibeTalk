package com.example.new_chart

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    // Forward new intents to Flutter engine so ZEGOCLOUD offline-call
    // accept/reject actions are properly delivered when the app is already
    // running in the background and gets brought to the foreground.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
