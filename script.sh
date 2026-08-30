#!/usr/bin/env bash
set -e

# Script kept for reference: explains how the vendored plugin was created.
# The patched copy in packages/ is the source of truth now — do NOT re-run
# this to "refresh" the plugin, it would overwrite the NO_ACTIVITY fix.
#
# Original vendoring (for documentation only):
#   git clone --depth 1 https://github.com/clash-sing/flutter_sing_box.git packages/flutter_sing_box_patched
#   rm -rf packages/flutter_sing_box_patched/{.git,ios,example,test}
#
# Patches applied on top (all present in the repo already):
#   1. FlutterSingBoxPlugin.kt — deferred init until activity attaches
#      (fixes NO_ACTIVITY race), stopVpn error handling.
#   2. android/consumer-rules.pro — R8 keep rules for SFA services/AIDL.

echo "The vendored plugin is already patched in-tree. Nothing to do."
echo "If you need to re-vendor from upstream, see the instructions above."
