import 'dart:io';
import 'models/proxy.dart';

/// Everything plugin-specific lives behind this interface. If you swap
/// flutter_sing_box for a different wrapper later, this is the only file
/// that needs to change — the rest of the app just calls these methods.
abstract class ProxyEngine {
  /// One-time setup (loading the native core, etc).
  Future<void> init();

  /// Layers 2+3 from your desktop pipeline: brings up a *local* proxy
  /// instance for this single config (no system-wide VPN, no VpnService
  /// permission prompt) and returns round-trip latency in ms, or null on
  /// failure. Must be safe to run many of these concurrently — this is
  /// what testing 20+ candidates at once depends on.
  ///
  /// IMPORTANT: verify your chosen plugin actually exposes a "local test
  /// only" mode distinct from "start system VPN". Not all sing-box Flutter
  /// wrappers separate the two — check before committing to one.
  Future<double?> testProxy(Proxy proxy, {required String testUrl, required Duration timeout});

  /// Starts the system-wide VPN tunnel using the winning proxy's config.
  /// This is the one call that triggers Android's VPN permission dialog.
  Future<void> connect(Proxy proxy);

  Future<void> disconnect();

  Stream<bool> get connectionStatus;
}

/// TCP-only reachability check — no plugin needed, works today.
/// This is Layer 1 from your desktop pipeline (equivalent to its
/// asyncio.open_connection-based tcp() method).
class TcpChecker {
  static Future<double?> check(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds.toDouble();
    } catch (_) {
      return null;
    }
  }
}
