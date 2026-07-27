#!/usr/bin/env bash
set -e

echo "==> Adding JitPack repository to android/build.gradle.kts..."
python3 - << 'PYEOF'
path = "android/build.gradle.kts"
with open(path) as f:
    content = f.read()

old = """allprojects {
    repositories {
        google()
        mavenCentral()
    }
}"""

new = """allprojects {
    repositories {
        google()
        mavenCentral()
        maven(\"https://jitpack.io\")
    }
}"""

assert old in content, "expected block not found — aborting to avoid partial patch"
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
git commit -m "Add JitPack repository for flutter_sing_box's native libbox dependency"
git push

echo "==> Done. Check Actions tab."