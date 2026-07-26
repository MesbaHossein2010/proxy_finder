#!/usr/bin/env bash
set -e

echo "==> Fixing DnsServer -> Server (correct class name/fields) in lib/singbox_engine.dart..."
python3 - << 'PYEOF'
path = "lib/singbox_engine.dart"
with open(path) as f:
    content = f.read()

old = "dns: Dns(servers: [DnsServer(tag: 'dns-out', address: '8.8.8.8')], rules: []),"
new = "dns: Dns(servers: [Server(tag: 'dns-out', type: 'udp', server: '8.8.8.8')], rules: []),"

assert old in content, "expected DnsServer line not found — aborting"
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
git commit -m "Fix Dns server class name (Server, not DnsServer) and correct fields"
git push

echo "==> Done. Check Actions tab."