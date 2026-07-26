#!/usr/bin/env bash
set -e

echo "==> Clearing stale pub git cache for flutter_sing_box..."
rm -rf ~/.pub-cache/git/cache/flutter_sing_box-*
rm -rf ~/.pub-cache/git/flutter_sing_box-*

echo "==> Adding package_info_plus override alongside device_info_plus..."
python3 - << 'PYEOF'
path = "pubspec.yaml"
with open(path) as f:
    content = f.read()

content = content.replace(
    'device_info_plus: ">=9.0.0 <11.0.0"',
    'device_info_plus: ">=9.0.0 <11.0.0"\n  package_info_plus: ">=7.0.0 <9.0.0"'
)

with open(path, "w") as f:
    f.write(content)
print("pubspec.yaml updated with package_info_plus override.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Clear stale git cache; override package_info_plus alongside device_info_plus"
git push

echo "==> Done. Check Actions tab."