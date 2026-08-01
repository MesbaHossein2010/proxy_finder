#!/usr/bin/env bash
set -e

echo "==> Vendoring flutter_sing_box into packages/ so we can patch it directly..."
mkdir -p packages
rm -rf packages/flutter_sing_box_patched
git clone --depth 1 https://github.com/clash-sing/flutter_sing_box.git packages/flutter_sing_box_patched
rm -rf packages/flutter_sing_box_patched/.git
rm -rf packages/flutter_sing_box_patched/ios
rm -rf packages/flutter_sing_box_patched/example
rm -rf packages/flutter_sing_box_patched/test

echo "==> Patching FlutterSingBoxPlugin.kt to log every activity attach/detach event,"
echo "    and include that history directly in the NO_ACTIVITY error message..."
python3 - << 'PYEOF'
path = "packages/flutter_sing_box_patched/android/src/main/kotlin/com/clashsing/flutter_sing_box/FlutterSingBoxPlugin.kt"
with open(path) as f:
    content = f.read()

# Add an event log field right after activityBinding declaration
old_field = "    private var activityBinding: ActivityPluginBinding? = null"
new_field = old_field + "\n    private val eventLog = mutableListOf<String>()"
assert old_field in content
content = content.replace(old_field, new_field, 1)

# Log every lifecycle transition
content = content.replace(
    'Log.d(TAG, "onAttachedToActivity --------------------")\n        activityBinding = binding',
    'Log.d(TAG, "onAttachedToActivity --------------------")\n        eventLog.add("attached")\n        activityBinding = binding'
)
content = content.replace(
    'Log.d(TAG, "onDetachedFromActivityForConfigChanges --------------------")\n        activityBinding?.removeActivityResultListener(this)\n        activityBinding = null',
    'Log.d(TAG, "onDetachedFromActivityForConfigChanges --------------------")\n        eventLog.add("detachedForConfigChanges")\n        activityBinding?.removeActivityResultListener(this)\n        activityBinding = null'
)
content = content.replace(
    'Log.d(TAG, "onReattachedToActivityForConfigChanges --------------------")\n        activityBinding = binding',
    'Log.d(TAG, "onReattachedToActivityForConfigChanges --------------------")\n        eventLog.add("reattached")\n        activityBinding = binding'
)
content = content.replace(
    'Log.d(TAG, "onDetachedFromActivity --------------------")\n        singBoxConnector?.disconnect()',
    'Log.d(TAG, "onDetachedFromActivity --------------------")\n        eventLog.add("detached")\n        singBoxConnector?.disconnect()'
)

# Make both NO_ACTIVITY error messages include the full event history
content = content.replace(
    'result.error("NO_ACTIVITY", "无法获取Activity实例", null)',
    'result.error("NO_ACTIVITY", "无法获取Activity实例 | events=" + eventLog.joinToString(">") + " | bindingNull=" + (activityBinding == null), null)'
)

with open(path, "w") as f:
    f.write(content)
print("Patched.")
PYEOF

echo "==> Switching pubspec.yaml to use the local patched copy instead of the git version..."
python3 - << 'PYEOF'
import re
path = "pubspec.yaml"
with open(path) as f:
    content = f.read()

old = """  flutter_sing_box:
    git:
      url: https://github.com/clash-sing/flutter_sing_box.git
"""
new = """  flutter_sing_box:
    path: packages/flutter_sing_box_patched
"""
assert old in content, "expected git dependency block not found — aborting"
content = content.replace(old, new)

with open(path, "w") as f:
    f.write(content)
print("pubspec.yaml updated.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing (this includes vendoring the plugin source, so it's a bigger commit)..."
git add .
git commit -m "Vendor flutter_sing_box locally with activity-lifecycle diagnostic logging"
git push

echo "==> Done. Once built and installed, tap Start Test and read me the FULL error text —"
echo "    it now includes the exact attach/detach event history, which tells us definitively"
echo "    whether onAttachedToActivity ever fired at all."