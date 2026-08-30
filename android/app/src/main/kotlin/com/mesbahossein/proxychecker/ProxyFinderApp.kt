package com.mesbahossein.proxychecker

import android.app.ActivityManager
import android.content.Context
import com.clashsing.flutter_sing_box.cs.PluginManager
import io.flutter.app.FlutterApplication

/**
 * Application entry point.
 *
 * Runs in EVERY process of the app, including the ":remote" process that
 * hosts BoxService (the VPN service). MMKV must be initialized before any
 * MMKV.mmkvWithID() call in any process, otherwise the VPN service crashes
 * with "You should Call MMKV.initialize() first".
 *
 * Extends FlutterApplication so the Flutter engine still registers plugins
 * correctly in the main process.
 */
class ProxyFinderApp : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()

        // MMKV init must run unconditionally in every process.
        // It is cheap and idempotent; initialize() is a no-op after the
        // first real call in this process.
        PluginManager.initializeMmkv(this)

        // PluginManager.init() does Flutter-plugin-wiring + Libbox setup.
        // Only run it in the main process; in :remote the Flutter engine
        // does not exist and the plugin will attach later in main.
        if (isMainProcess()) {
            try {
                PluginManager.init(this)
            } catch (e: Exception) {
                // Never crash the app on startup if a plugin subsystem
                // fails to initialize. The plugin will retry when the
                // engine attaches.
                e.printStackTrace()
            }
        }
    }

    private fun isMainProcess(): Boolean {
        val pid = android.os.Process.myPid()
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processName = manager.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName
        return processName == packageName
    }
}