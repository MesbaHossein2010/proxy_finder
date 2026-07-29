#!/usr/bin/env bash
set -e

echo "==> Setting minSdk to 26 (required by flutter_sing_box)..."
python3 - << 'PYEOF'
path = "android/app/build.gradle.kts"
with open(path) as f:
    content = f.read()

old = "minSdk = flutter.minSdkVersion"
new = "minSdk = 26"

assert old in content, "expected minSdk line not found — aborting"
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
git commit -m "Bump minSdk to 26 as required by flutter_sing_box"
git push

echo "==> Done. Check Actions tab."