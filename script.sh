#!/usr/bin/env bash
set -e

echo "==> Patching lib/main.dart: remove Connect button (copy-only), default URL..."

python3 - << 'PYEOF'
import re
path = "lib/main.dart"
with open(path) as f:
    content = f.read()

# Set default URL value
content = content.replace(
    "final _urlController = TextEditingController();",
    'final _urlController = TextEditingController(text: "https://raw.githubusercontent.com/AzadNetCH/Clash/main/AzadNet.txt");'
)

# Remove connection-related state/logic
content = content.replace(
    "  bool _connected = false;\n  Proxy? _connectedProxy;\n\n",
    ""
)
content = re.sub(
    r"\n  Future<void> _toggleConnection\(\) async \{.*?\n  \}\n",
    "\n",
    content,
    flags=re.DOTALL
)
content = content.replace(
    "    engine.connectionStatus.listen((status) {\n      if (mounted) setState(() => _connected = status);\n    });\n",
    ""
)

# Replace the "Best proxy / connect" card with a copy-only card
old_card = re.search(r"            // --- Best proxy / connect ---\n            if \(best != null\).*?\n              \),\n", content, re.DOTALL)
if old_card:
    new_card = '''            // --- Best proxy (copy only, no connect) ---
            if (best != null)
              Card(
                color: const Color(0xFF1A1A2E),
                child: ListTile(
                  title: Text('Best: ${best.protocol} — ${best.server}'),
                  subtitle: Text('${best.latencyMs!.toStringAsFixed(0)} ms'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy URI',
                    onPressed: () => _copyUri(best.uri),
                  ),
                ),
              ),
'''
    content = content[:old_card.start()] + new_card + content[old_card.end():]

with open(path, "w") as f:
    f.write(content)

print("Patched successfully.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Remove Connect button (copy-only), set default subscription URL"
git push

echo "==> Done. Check Actions tab on GitHub."