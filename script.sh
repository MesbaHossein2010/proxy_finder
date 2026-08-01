#!/usr/bin/env bash
set -e

echo "==> Switching CI workflow to build debug APK (rules out R8/shrinking as the cause)..."
python3 - << 'PYEOF'
path = ".github/workflows/build.yml"
with open(path) as f:
    content = f.read()

content = content.replace(
    "run: flutter build apk --release",
    "run: flutter build apk --debug"
)
content = content.replace(
    "path: build/app/outputs/flutter-apk/app-release.apk",
    "path: build/app/outputs/flutter-apk/app-debug.apk"
)

with open(path, "w") as f:
    f.write(content)
print("Workflow updated to build debug APK.")
PYEOF

echo "==> Committing and pushing..."
git add .
git commit -m "Temporarily build debug APK to test if release R8 shrinking is causing NO_ACTIVITY"
git push

echo "==> Done. Once built, install this debug APK (uninstall the old one first,"
echo "    since debug/release builds can have different signing) and try Start Test again."