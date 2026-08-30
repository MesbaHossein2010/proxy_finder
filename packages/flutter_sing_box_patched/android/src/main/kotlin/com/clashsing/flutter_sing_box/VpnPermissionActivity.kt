package com.clashsing.flutter_sing_box

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/**
 * Transparent Activity that handles VPN consent synchronously.
 *
 * HyperOS/MIUI silently swallows VPN consent intents launched from a
 * Flutter plugin's MethodChannel hop because the async call loses the
 * "direct user gesture" signal. This Activity calls VpnService.prepare()
 * and startActivityForResult() inside its own onCreate — same call
 * stack, same thread, zero hops. HyperOS sees it as a normal foreground
 * activity transition and shows the dialog.
 */
class VpnPermissionActivity : Activity() {

    companion object {
        private const val REQUEST_CODE_VPN_PERMISSION = 24601

        /**
         * Static callback the plugin registers before launching this activity.
         * Called with true if permission granted, false otherwise.
         * Runs on the main thread (Activity lifecycle callback).
         */
        var callback: ((Boolean) -> Unit)? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val vpnIntent = VpnService.prepare(this)
        if (vpnIntent != null) {
            // Consent needed — launch system dialog synchronously.
            startActivityForResult(vpnIntent, REQUEST_CODE_VPN_PERMISSION)
        } else {
            // Already have permission.
            finishWithResult(true)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE_VPN_PERMISSION) {
            finishWithResult(resultCode == RESULT_OK)
        }
    }

    private fun finishWithResult(granted: Boolean) {
        callback?.invoke(granted)
        callback = null
        finish()
    }
}
