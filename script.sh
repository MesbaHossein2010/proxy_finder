#!/usr/bin/env bash
set -e

echo "==> Fixing broken string interpolation in lib/main.dart (was printing literal '\$e' instead of the real error)..."
python3 - << 'PYEOF'
path = "lib/main.dart"
with open(path) as f:
    content = f.read()

old = "_showSnack('Test failed: \\$e');"
new = "_showSnack('Test failed: $e');"

if old in content:
    content = content.replace(old, new)
    print("Fixed via exact match.")
else:
    # Fallback: catch any remaining literal backslash-dollar in a showSnack call
    import re
    content, n = re.subn(r"_showSnack\('Test failed: \\\$e'\)", "_showSnack('Test failed: $e')", content)
    print(f"Fixed {n} occurrence(s) via regex fallback.")

with open(path, "w") as f:
    f.write(content)
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Fix broken error string interpolation to actually show the real test failure"
git push

echo "==> Done. Check Actions tab, then run Start Test again and send me the actual error message."