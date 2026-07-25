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

  /// Sorts working proxies by latency and returns the fastest — same as
  /// desktop's "Copy Best" (min by latency among working proxies).
  static Proxy? pickBest(List<Proxy> tested) {
    final working = tested.where((p) => p.working == true && p.latencyMs != null).toList();
    if (working.isEmpty) return null;
    working.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    return working.first;
  }
}
