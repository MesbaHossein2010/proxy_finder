#!/bin/bash
set -e

echo "=== Waiting for emulator ==="
adb wait-for-device

echo "Waiting for boot (up to 10 min)..."
for i in $(seq 1 120); do
  BOOT=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "")
  if [ "$BOOT" = "1" ]; then
    echo "Boot complete at attempt $i"
    break
  fi
  sleep 5
done

echo "Cooling down 15s after boot..."
sleep 15

echo "=== Installing APK ==="
adb install /tmp/apk/app-debug.apk
adb shell pm grant com.mesbahossein.proxychecker android.permission.POST_NOTIFICATIONS 2>/dev/null || true

echo "=== Launching app ==="
adb shell am start -n com.mesbahossein.proxychecker/.MainActivity
sleep 15

echo "=== App alive check ==="
APP_PID=$(adb shell pidof com.mesbahossein.proxychecker 2>/dev/null || echo "")
if [ -z "$APP_PID" ]; then
  echo "FAIL: App crashed at launch"
  exit 1
fi
echo "PASS: App alive PID=$APP_PID"

# ---------------------------------------------------------------
# Interaction test helper: tap by fraction of screen size.
# ---------------------------------------------------------------
tap() { # tap <fx> <fy>
  SIZE=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | head -1)
  W=${SIZE%x*}; H=${SIZE#*x}
  X=$(( W * $1 / 100 )); Y=$(( H * $2 / 100 ))
  adb shell input tap "$X" "$Y"
}

echo "=== T1: VPN permission dialog fires at launch ==="
sleep 5
DIALOG=$(adb shell dumpsys window 2>/dev/null | grep -c "VpnDialog\|VpnService" || true)
LOG_PREP=$(adb logcat -d | grep -c "startVpn\|prepareVpn" || true)
if [ "$DIALOG" -gt 0 ] || [ "$LOG_PREP" -gt 0 ]; then
  echo "PASS: VPN consent flow triggered"
else
  echo "WARN: no VPN dialog trace (emulator may auto-consent)"
fi
# Dismiss the consent dialog if present (Allow button is right side)
adb shell input keyevent KEYCODE_BACK 2>/dev/null || true
sleep 3

echo "=== T2: Load sample proxies from clipboard ==="
adb shell input text "ss://YWVzLTI1Ni1nY206dGVzdA@1.2.3.4:8388#test1"
sleep 1
tap 50 85   # add/parse button area
sleep 3

echo "=== T3: Open second tab ==="
tap 83 50
sleep 3

echo "=== T4: Back to first tab ==="
tap 17 50
sleep 2

echo "=== T5: Scroll through list ==="
adb shell input swipe 360 600 360 200 300
sleep 2

echo "=== Logcat: Crashes (before final state check) ==="
adb logcat -d | grep -iE "FATAL|AndroidRuntime|SIGABRT|SIGSEGV|Exception|Error" | tail -30 || true
echo "--- kernel log (OOM/ANR) ---"
adb shell dmesg 2>/dev/null | grep -iE "lowmemorykiller|oom|kill|anr" | tail -10 || true
echo "--- process list ---"
adb shell ps -A 2>/dev/null | grep -i "proxychecker\|nekohasekai" || echo "no proxychecker process"

echo "=== Final app state ==="
sleep 5
ALIVE=$(adb shell pidof com.mesbahossein.proxychecker 2>/dev/null || echo "")
if [ -z "$ALIVE" ]; then
  echo "FAIL: App died during interaction"
  adb logcat -d | grep -iE "FATAL|AndroidRuntime|SIGABRT|SIGSEGV" | tail -20 || true
  exit 1
fi
echo "PASS: survived all interactions"

echo "=== Logcat: Crashes ==="
adb logcat -d | grep -iE "FATAL|AndroidRuntime|SIGABRT|SIGSEGV" | tail -20 || true

echo "=== Verdict ==="
CRASH=$(adb logcat -d | grep -c "FATAL\|AndroidRuntime.*Exception" || true)
ALIVE2=$(adb shell pidof com.mesbahossein.proxychecker 2>/dev/null || echo "")
if [ "$CRASH" -gt 0 ]; then
  echo "FAIL: $CRASH crash(es) during interaction"
  exit 1
elif [ -z "$ALIVE2" ]; then
  echo "FAIL: App not running"
  exit 1
else
  echo "PASS: No crashes, app alive, interactions done"
fi
