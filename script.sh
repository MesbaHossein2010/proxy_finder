#!/usr/bin/env bash
set -e

echo "==> Adding required MMKV.initialize() before app starts..."
python3 - << 'PYEOF'
path = "lib/main.dart"
with open(path) as f:
    content = f.read()

old = """void main() {
  runApp(const ProxyCheckerApp());
}"""

new = """void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  runApp(const ProxyCheckerApp());
}"""

assert old in content, "expected main() block not found — aborting"
content = content.replace(old, new)

# Add the mmkv import alongside the existing flutter/material import
old_import = "import 'package:flutter/material.dart';"
new_import = "import 'package:flutter/material.dart';\nimport 'package:mmkv/mmkv.dart';"
assert old_import in content
content = content.replace(old_import, new_import, 1)

with open(path, "w") as f:
    f.write(content)
print("Fixed.")
PYEOF

echo "==> Adding mmkv as an explicit dependency (flutter_sing_box uses it transitively, but we call it directly now)..."
python3 - << 'PYEOF'
path = "pubspec.yaml"
with open(path) as f:
    content = f.read()

marker = "  path_provider: ^2.1.0\n"
if "mmkv:" not in content:
    content = content.replace(marker, marker + "  mmkv: ^2.0.1\n")

with open(path, "w") as f:
    f.write(content)
print("pubspec.yaml updated.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Initialize MMKV before app start, as required by flutter_sing_box's profile storage"
git push

echo "==> Done. Check Actions tab, then try Start Test again on your phone."