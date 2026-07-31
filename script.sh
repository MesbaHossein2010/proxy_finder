#!/usr/bin/env bash
set -e

echo "==> Ensuring singBoxEngine.init() is properly awaited right before testing starts..."
python3 - << 'PYEOF'
path = "lib/main.dart"
with open(path) as f:
    content = f.read()

old = """    try {
      final tagResults = await singBoxEngine.testGroup(_proxies);"""

new = """    try {
      // Re-run init() here (awaited) so we're certain the Android Activity
      // is attached — the earlier initState() call wasn't awaited and may
      // have silently failed if the Activity wasn't ready at app cold start.
      await singBoxEngine.init();
      final tagResults = await singBoxEngine.testGroup(_proxies);"""

assert old in content, "expected try block start not found — aborting"
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
git commit -m "Re-await engine init before testing to fix NO_ACTIVITY race condition"
git push

echo "==> Done. Check Actions tab, then try Start Test again."