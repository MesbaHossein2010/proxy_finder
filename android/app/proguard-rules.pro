# === proxy_checker_mobile R8 rules ===
# Keep all sing-box and plugin classes from being removed by R8.
# These are referenced by Android service binding and the Flutter plugin system.

# Plugin + connector
-keep class com.clashsing.flutter_sing_box.** { *; }

# SFA background services (VPN, BootReceiver, BoxService, AIDL)
-keep class io.nekohasekai.sfa.bg.** { *; }

# AIDL service interfaces (referenced at runtime by bindService)
-keep interface io.nekohasekai.sfa.aidl.** { *; }
-keep class io.nekohasekai.sfa.aidl.**$* { *; }

# sing-box native library
-keep class io.nekohasekai.libbox.** { *; }

# Flutter plugin registration
-keep class io.flutter.plugins.** { *; }

# Keep enums used by sing-box models (serialized/deserialized via Gson/etc)
-keepclassmembers enum * {
    **[] $VALUES;
    public *;
}

# Prevent Kotlin metadata stripping that can break reflection-heavy plugins
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# Keep all subclasses of VpnService (Android resolves these by class name)
-keep class * extends android.net.VpnService { *; }
