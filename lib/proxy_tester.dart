import 'dart:async';
import 'models/proxy.dart';
import 'proxy_engine.dart';

const defaultTestUrl = 'http://www.gstatic.com/generate_204';

/// Port of your desktop TestWorker/_dt/ftwv logic:
///   Layer 1 — TCP reachability (fast, filters dead servers)
///   Layer 2 — full tunnel test via the engine (real HTTP through the proxy)
///   Layer 3 — validation retest after a short delay, catches flaky proxies
/// A proxy must pass all three to be marked working — same rule as desktop.
class ProxyTester {
  final ProxyEngine engine;
  final String testUrl;
  final Duration timeout;

  ProxyTester(this.engine, {this.testUrl = defaultTestUrl, this.timeout = const Duration(seconds: 4)});

  Future<Proxy> testOne(Proxy proxy) async {
    // Layer 1
    final tcpLatency = await TcpChecker.check(proxy.server, proxy.port, timeout: timeout);
    if (tcpLatency == null) {
      return proxy.copyWithResult(working: false, testType: 'tcp_fail');
    }

    // Layer 2
    final l2Latency = await engine.testProxy(proxy, testUrl: testUrl, timeout: timeout);
    if (l2Latency == null) {
      return proxy.copyWithResult(working: false, latencyMs: tcpLatency, testType: 'full_fail');
    }

    // Layer 3 — same 0.3s gap as desktop, then a second request through
    // the same tunnel to catch "works once, dies right after" proxies
    await Future.delayed(const Duration(milliseconds: 300));
    final l3Latency = await engine.testProxy(proxy, testUrl: testUrl, timeout: timeout);
    if (l3Latency == null) {
      return proxy.copyWithResult(working: false, latencyMs: l2Latency, testType: 'validation_fail');
    }

    return proxy.copyWithResult(working: true, latencyMs: l3Latency, testType: 'full');
  }

  /// Tests a batch with bounded concurrency (same purpose as desktop's
  /// asyncio.Semaphore(concurrency)), streaming each result as it lands.
  Stream<Proxy> testAll(List<Proxy> proxies, {int concurrency = 10}) {
    final controller = StreamController<Proxy>();
    var index = 0;
    var active = 0;
    var completed = 0;

    void pump() {
      while (active < concurrency && index < proxies.length) {
        final proxy = proxies[index++];
        active++;
        testOne(proxy).then((result) {
          active--;
          completed++;
          controller.add(result);
          if (completed == proxies.length) {
            controller.close();
          } else {
            pump();
          }
        });
      }
    }

    pump();
    if (proxies.isEmpty) controller.close();
    return controller.stream;
  }

  /// Port of desktop's tsp() — runs several requests through the same
  /// proxy and reports avg/min/max/jitter/success rate.
  Future<SpeedData?> speedTest(Proxy proxy, {int iterations = 3}) async {
    final latencies = <double>[];
    for (var i = 0; i < iterations; i++) {
      final latency = await engine.testProxy(proxy, testUrl: testUrl, timeout: timeout);
      if (latency != null) latencies.add(latency);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (latencies.isEmpty) return null;

    final avg = latencies.reduce((a, b) => a + b) / latencies.length;
    final jitter = latencies.length > 1
        ? latencies.map((l) => (l - avg).abs()).reduce((a, b) => a + b) / latencies.length
        : 0.0;
    final min = latencies.reduce((a, b) => a < b ? a : b);
    final max = latencies.reduce((a, b) => a > b ? a : b);

    return SpeedData(
      avgMs: avg,
      minMs: min,
      maxMs: max,
      jitterMs: jitter,
      successRate: (latencies.length / iterations) * 100,
    );
  }

  /// Sorts working proxies by latency and returns the fastest — same as
  /// desktop's "Copy Best" (min by latency among working proxies).
  static Proxy? pickBest(List<Proxy> tested) {
    final working = tested.where((p) => p.working == true && p.latencyMs != null).toList();
    if (working.isEmpty) return null;
    working.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    return working.first;
  }

  /// Full results list sorted for display: working proxies first (fastest
  /// to slowest), failed proxies after.
  static List<Proxy> sortedForDisplay(List<Proxy> tested) {
    final sorted = List<Proxy>.from(tested);
    sorted.sort((a, b) {
      final aOk = a.working == true;
      final bOk = b.working == true;
      if (aOk != bOk) return aOk ? -1 : 1;
      if (aOk && bOk) {
        final aLat = a.latencyMs ?? double.infinity;
        final bLat = b.latencyMs ?? double.infinity;
        return aLat.compareTo(bLat);
      }
      return 0;
    });
    return sorted;
  }

  /// Runs the real group-based test via SingBoxTestEngine and maps
  /// results back onto Proxy objects using the same tag scheme.
  static List<Proxy> applyGroupResults(
    List<Proxy> proxies,
    Map<String, double?> tagToLatency,
    String Function(dynamic) tagFor,
  ) {
    return proxies.map((p) {
      final latency = tagToLatency[tagFor(p)];
      if (latency == null) {
        return p.copyWithResult(working: false, testType: 'group_test_fail');
      }
      return p.copyWithResult(working: true, latencyMs: latency, testType: 'group_test_ok');
    }).toList();
  }
}
