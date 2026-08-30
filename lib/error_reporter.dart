import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

/// Builds a self-contained diagnostic report for any app error.
///
/// Contains: app version, device model, Android version, engine state,
/// and the error itself. Shared via the Android share sheet — no network
/// permission needed, works fully offline.
class ErrorReporter {
  /// Build the full report text.
  static Future<String> buildReport({
    required String where,
    required Object error,
    StackTrace? stack,
    bool engineReady = false,
    bool vpnStarted = false,
  }) async {
    final buf = StringBuffer();

    // ---- app info ----
    String appInfo = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appInfo = '${info.version} (${info.buildNumber})';
    } catch (_) {}

    // ---- device info ----
    String device = 'unknown';
    String android = 'unknown';
    try {
      final di = DeviceInfoPlugin();
      final and = await di.androidInfo;
      device = '${and.manufacturer} ${and.model}';
      android = 'Android ${and.version.release} (SDK ${and.version.sdkInt})';
    } catch (_) {}

    buf.writeln('=== Proxy Finder error report ===');
    buf.writeln('time: ${DateTime.now().toIso8601String()}');
    buf.writeln('where: $where');
    buf.writeln('app: $appInfo');
    buf.writeln('device: $device');
    buf.writeln('os: $android');
    buf.writeln('engine_ready: $engineReady');
    buf.writeln('vpn_started: $vpnStarted');
    buf.writeln();
    buf.writeln('--- error ---');
    buf.writeln(error.toString());
    if (stack != null) {
      buf.writeln();
      buf.writeln('--- stack ---');
      buf.writeln(stack.toString());
    }
    return buf.toString();
  }

  /// Show an error snackbar with a "Report" action. Works from any
  /// BuildContext (pass a State object or its context).
  static void showError(
    dynamic host, {
    required String where,
    required Object error,
    StackTrace? stack,
    String? fallbackText,
    bool engineReady = false,
    bool vpnStarted = false,
  }) {
    final ctx = switch (host) {
      State s => s.context,
      _ => host as BuildContext?,
    };
    if (ctx == null || !ctx.mounted) return;

    final shortMsg =
        fallbackText ?? _shorten(error);

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(shortMsg),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Report',
          onPressed: () => showReportDialog(
            ctx,
            where: where,
            error: error,
            stack: stack,
            engineReady: engineReady,
            vpnStarted: vpnStarted,
          ),
        ),
      ),
    );
  }

  /// Dialog with the full report + Copy + Share buttons.
  static Future<void> showReportDialog(
    BuildContext context, {
    required String where,
    required Object error,
    StackTrace? stack,
    bool engineReady = false,
    bool vpnStarted = false,
  }) async {
    final report = await buildReport(
      where: where,
      error: error,
      stack: stack,
      engineReady: engineReady,
      vpnStarted: vpnStarted,
    );
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Error report'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              Navigator.of(dctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report copied')),
              );
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
            onPressed: () async {
              Navigator.of(dctx).pop();
              await SharePlus.instance.share(
                ShareParams(text: report, subject: 'Proxy Finder error report'),
              );
            },
          ),
        ],
      ),
    );
  }

  /// One-line friendly version of an error for the snackbar.
  static String _shorten(Object error) {
    var s = error.toString();
    s = s.replaceFirst(RegExp(r'^(Exception|PlatformException\([^)]*\)):\s*'), '');
    if (s.length > 120) s = '${s.substring(0, 117)}...';
    return s;
  }
}
