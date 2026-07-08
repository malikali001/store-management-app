package com.storemanager.store_manager

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's BiometricPrompt requires a FragmentActivity, so we extend
// FlutterFragmentActivity (not FlutterActivity) — otherwise authenticate()
// fails with "no_fragment_activity" and biometrics silently do nothing.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and hide app contents in the recent-apps switcher,
        // so financial data is not captured or previewed off-app.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
