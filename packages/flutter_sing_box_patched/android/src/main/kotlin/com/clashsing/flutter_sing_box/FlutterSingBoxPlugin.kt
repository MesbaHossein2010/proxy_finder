package com.clashsing.flutter_sing_box

import android.content.Intent
import android.net.VpnService
import android.util.Log
import com.clashsing.flutter_sing_box.cs.PluginManager
import com.clashsing.flutter_sing_box.cs.SingBoxConnector
import com.clashsing.flutter_sing_box.utils.SettingsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.sfa.bg.BoxService
import java.util.concurrent.atomic.AtomicReference

class FlutterSingBoxPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    companion object {
        private const val TAG = "FlutterSingBoxPlugin"
        private const val METHOD_CHANNEL_NAME = "flutter_sing_box_method"
        private const val VPN_REQUEST_CODE = 1001
    }

    private lateinit var channel: MethodChannel
    private var singBoxConnector: SingBoxConnector? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val eventLog = mutableListOf<String>()
    private val pendingStartVpnResult = AtomicReference<Result?>(null)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        PluginManager.init(flutterPluginBinding.applicationContext)
        singBoxConnector = SingBoxConnector(flutterPluginBinding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        channel.setMethodCallHandler(null)
        singBoxConnector = null
        pendingStartVpnResult.set(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                Log.d(TAG, "init")
                // Always succeed fast: init must never hang. The service
                // binding continues in the background; startVpn()/urlTest()
                // will wait for it when actually needed.
                try {
                    activityBinding?.activity?.let { act -> singBoxConnector?.connect(act) }
                } catch (e: Exception) {
                    Log.e(TAG, "init connect failed (non-fatal)", e)
                }
                result.success(null)
            }
            "prepareVpn" -> {
                // Works from app context — consent state is app-wide.
                val ctx = try { PluginManager.appContext } catch (_: Exception) { null }
                if (ctx == null) {
                    result.error("PLUGIN_NOT_INIT", "Plugin not initialised. Reopen the app.", null)
                    return
                }
                val intent = VpnService.prepare(ctx)
                result.success(intent == null) // true = already granted, false = dialog needed
            }
            "startVpn" -> {
                // Path 1: consent already granted — start the service
                // directly. No activity needed.
                val appCtx = try { PluginManager.appContext } catch (_: Exception) { null }
                val act = activityBinding?.activity
                val ctx = act ?: appCtx
                if (ctx == null) {
                    result.error("NO_ACTIVITY", "Plugin not initialised (no context). Reopen the app.", null)
                    return
                }
                if (VpnService.prepare(ctx) == null) {
                    Log.d(TAG, "startVpn: consent already granted, starting service")
                    startVpnService(result)
                    return
                }
                // Path 2: consent needed — launch VpnPermissionActivity.
                // This transparent Activity calls VpnService.prepare() and
                // startActivityForResult() inside its own onCreate — same
                // call stack, same thread, zero MethodChannel hops. HyperOS
                // sees it as a normal foreground transition and shows the
                // VPN consent dialog. Direct launches from the Flutter
                // plugin's MethodChannel hop get silently swallowed because
                // the async channel round-trip loses the "user gesture"
                // signal that HyperOS/MIUI requires.
                Log.d(TAG, "startVpn: launching VpnPermissionActivity (act=${act != null})")
                eventLog.add("vpnPermAct(act=${act != null})")
                // Re-entry guard
                val oldPending = pendingStartVpnResult.get()
                if (oldPending != null) {
                    if (act == null) {
                        Log.d(TAG, "startVpn: clearing stale pending (activity gone)")
                        eventLog.add("clearedStalePending")
                        pendingStartVpnResult.set(null)
                    } else {
                        eventLog.add("alreadyPending")
                        result.error("ALREADY_WAITING", "VPN permission dialog is already open. Answer it.", null)
                        return
                    }
                }
                // Register callback before launching so we don't miss it.
                VpnPermissionActivity.callback = { granted ->
                    // This fires on the main thread from Activity lifecycle.
                    val r = pendingStartVpnResult.getAndSet(null)
                    if (r != null) {
                        if (granted) {
                            eventLog.add("vpnPermGranted")
                            startVpnService(r)
                        } else {
                            eventLog.add("vpnPermDenied")
                            r.error("VPN_PERMISSION_DENIED", "VPN permission denied by user.", null)
                        }
                    }
                }
                pendingStartVpnResult.set(result)
                try {
                    val permIntent = Intent(ctx, VpnPermissionActivity::class.java)
                    if (act != null) {
                        // Launch from activity context — no NEW_TASK needed.
                        act.startActivity(permIntent)
                    } else {
                        // Fallback: app context needs NEW_TASK.
                        permIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        ctx.startActivity(permIntent)
                    }
                } catch (e: Exception) {
                    pendingStartVpnResult.set(null)
                    VpnPermissionActivity.callback = null
                    eventLog.add("permActFailed:${e.javaClass.simpleName}")
                    result.error("NO_ACTIVITY", "Could not open VPN permission dialog: ${e.message}. Bring the app to front and tap Test again.", null)
                    return
                }
            }
            "stopVpn" -> {
                try {
                    BoxService.stop()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("VPN_STOP_FAILED", "Failed to stop VPN: ${e.message}", null)
                }
            }
            "serviceReload" -> {
                try {
                    Libbox.newStandaloneCommandClient().serviceReload()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SERVICE_RELOAD_FAILED", "Service reload failed: ${e.message}", null)
                }
            }
            "setClashMode" -> {
                val clashMode = call.arguments as String
                if (singBoxConnector?.clientClashMode?.modes?.contains(clashMode) == true) {
                    Libbox.newStandaloneCommandClient().setClashMode(clashMode)
                    singBoxConnector?.clashModeClient?.connect()
                    result.success(null)
                } else {
                    result.error("INVALID_CLASH_MODE", "Invalid Clash mode: $clashMode", null)
                }
            }
            "selectOutbound" -> {
                val groupArgName = "groupTag"
                val outboundArgName = "outboundTag"
                if (call.arguments !is Map<*, *>) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
                    return
                }
                val argsMap = call.arguments as Map<*, *>
                val groupTag = argsMap[groupArgName] as String?
                val outboundTag = argsMap[outboundArgName] as String?
                if (groupTag.isNullOrBlank() || outboundTag.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
                    return
                }
                try {
                    Libbox.newStandaloneCommandClient().selectOutbound(groupTag, outboundTag)
                    singBoxConnector?.groupClient?.connect()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments: ${e.message}", null)
                }
            }
            "setGroupExpand" -> {
                val groupArgName = "groupTag"
                val expandArgName = "isExpand"
                if (call.arguments !is Map<*, *>) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
                    return
                }
                val argsMap = call.arguments as Map<*, *>
                val groupTag = argsMap[groupArgName] as String?
                val isExpand = argsMap[expandArgName] as Boolean?
                if (groupTag.isNullOrBlank() || isExpand == null) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
                    return
                }
                try {
                    Libbox.newStandaloneCommandClient().setGroupExpand(groupTag, isExpand)
                    singBoxConnector?.groupClient?.connect()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments: ${e.message}", null)
                }
            }
            "urlTest" -> {
                val groupTag = call.arguments as String?
                if (groupTag.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
                    return
                }
                try {
                    Libbox.newStandaloneCommandClient().urlTest(groupTag)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INVALID_ARGUMENTS", "URL test failed: ${e.message}", null)
                }
            }
            "getSingBoxVersion" -> {
                val version = Libbox.version()
                result.success(version)
            }
            "isCommandSocketReady" -> {
                // True readiness probe: try to actually CONNECT to the
                // command socket. File.exists() can lie (a bind() leaves the
                // inode but the service may not be accepting). Connecting
                // answers "is anything listening" rather than "does a file
                // exist". No side effects — we connect and immediately close.
                try {
                    val ctx = PluginManager.appContext
                    val path = java.io.File(ctx.filesDir, "command.sock").absolutePath
                    val ready = try {
                        val s = android.net.LocalSocket()
                        s.connect(android.net.LocalSocketAddress(
                            path, android.net.LocalSocketAddress.Namespace.FILESYSTEM))
                        s.close()
                        true
                    } catch (_: Exception) {
                        false
                    }
                    result.success(ready)
                } catch (e: Exception) {
                    result.error("SOCKET_CHECK_FAILED", "Socket check failed: ${e.message}", null)
                }
            }
            "diagnostics" -> {
                // Round-5 ground-truth telemetry: answers "is the :remote process
                // actually torn down?" (Pid same/diff) and "did config + socket land?"
                val ctx = PluginManager.appContext
                val am = ctx.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val remoteProc = am.runningAppProcesses?.find { it.processName.endsWith(":remote") }
                val socket = java.io.File(ctx.filesDir, "command.sock")
                val configFile = com.clashsing.flutter_sing_box.utils.ProfileManager.getUsingConfig()
                result.success(mapOf(
                    "remoteProcessAlive" to (remoteProc != null),
                    "remoteProcessPid" to remoteProc?.pid,
                    "socketExists" to socket.exists(),
                    "configExists" to configFile.exists(),
                    "configNonEmpty" to (configFile.exists() && configFile.length() > 0),
                ))
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startVpnService(result: Result) {
        try {
            // Force a real OS-level service stop before starting again.
            // HyperOS freezes the :remote process (killing the tunnel and
            // command socket) WITHOUT invoking onDestroy()/onRevoke(). The
            // libbox BoxService keeps a stale in-memory 'status' != Stopped,
            // so a plain BoxService.start() redelivers to the same surviving
            // Service object whose onStartCommand() bails early (START_NOT_STICKY)
            // — no restart, no new command.sock. BoxService.stop() is NOT
            // reliable here either: it is an app-level broadcast that is
            // silently dropped when the :remote process is frozen.
            // Context.stopService() is handled by ActivityManagerService and
            // tears the Service down regardless of its internal state, so the
            // next start triggers onCreate() afresh -> brand-new BoxService
            // with status = Stopped.
            val appCtx = PluginManager.appContext
            appCtx.stopService(Intent(appCtx, SettingsManager.serviceClass()))
            BoxService.start()
            result.success(null)
        } catch (e: Exception) {
            result.error("VPN_ERROR", "Failed to start VPN: ${e.message}", null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "onAttachedToActivity")
        eventLog.add("attached")
        activityBinding = binding
        binding.addActivityResultListener(this)
        try {
            singBoxConnector?.connect(binding.activity)
        } catch (e: Exception) {
            Log.e(TAG, "connect on attach failed", e)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "onDetachedFromActivityForConfigChanges")
        eventLog.add("detachedForConfig")
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "onReattachedToActivityForConfigChanges")
        eventLog.add("reattached")
        activityBinding = binding
        binding.addActivityResultListener(this)
        try {
            singBoxConnector?.connect(binding.activity)
        } catch (e: Exception) {
            Log.e(TAG, "connect on reattach failed", e)
        }
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "onDetachedFromActivity")
        eventLog.add("detached")
        // Only disconnect if VPN is NOT running. This prevents the service
        // binding from being killed during activity lifecycle transitions
        // while the VPN is active. On HyperOS, disconnecting even when VPN
        // is off can cause issues, so we guard with a try-catch.
        try {
            singBoxConnector?.disconnect()
        } catch (_: Exception) {}
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == VPN_REQUEST_CODE) {
            val r = pendingStartVpnResult.getAndSet(null)
            if (r != null) {
                if (resultCode == android.app.Activity.RESULT_OK) {
                    eventLog.add("consentGranted")
                    startVpnService(r)
                } else {
                    eventLog.add("consentDenied")
                    r.error("VPN_PERMISSION_DENIED", "VPN permission denied by user.", null)
                }
            }
            return true
        }
        return false
    }
}
