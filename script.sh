#!/usr/bin/env bash
set -e

echo "==> Adding step-by-step diagnostics to isolate exactly which call fails..."
python3 - << 'PYEOF'
path = "lib/main.dart"
with open(path) as f:
    content = f.read()

old = """    try {
      // Re-run init() here (awaited) so we're certain the Android Activity
      // is attached — the earlier initState() call wasn't awaited and may
      // have silently failed if the Activity wasn't ready at app cold start.
      await singBoxEngine.init();
      final tagResults = await singBoxEngine.testGroup(_proxies);"""

new = """    try {
      _showSnack('Step 1: calling init()...');
      await singBoxEngine.init();
      _showSnack('Step 1 OK. Step 2: building profile + starting VPN...');
      final tagResults = await singBoxEngine.testGroup(_proxies);
      _showSnack('Step 2 OK.');"""

assert old in content, "expected try block not found — aborting"
content = content.replace(old, new)

with open(path, "w") as f:
    f.write(content)
print("Fixed.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Add step-by-step diagnostics to isolate NO_ACTIVITY failure point"
git push

echo "==> Done. Check Actions tab, install, tap Start Test, and tell me exactly"
echo "    which step message appears last before the error."