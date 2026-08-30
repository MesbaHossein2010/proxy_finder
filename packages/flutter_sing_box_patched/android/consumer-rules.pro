# Keep plugin service classes from being stripped by R8 — their names are
# referenced via reflection by Android's VpnService.startForeground() and the
# AIDL bind path. Removing them causes NO_ACTIVITY or missing-class crashes
# in release builds.

-keep class io.nekohasekai.sfa.bg.** { *; }
-keep class com.clashsing.flutter_sing_box.** { *; }
-keep class io.flutter.plugins.** { *; }

# sing-box native library — never rename or strip
-keep class io.nekohasekai.libbox.** { *; }

# AIDL service interfaces
-keep interface io.nekohasekai.sfa.aidl.** { *; }
-keep class io.nekohasekai.sfa.aidl.**$* { *; }
