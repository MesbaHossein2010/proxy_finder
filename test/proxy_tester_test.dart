import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:proxy_checker_mobile/models/proxy.dart';
import 'package:proxy_checker_mobile/proxy_engine.dart';
import 'package:proxy_checker_mobile/proxy_tester.dart';

/// Deterministic fake engine: first N calls succeed with a known latency,
/// then fail — lets us test the 3-layer logic without network.
class FakeEngine implements ProxyEngine {
  final List<double?> results;
  int calls = 0;

  FakeEngine(this.results);

  @override
  Future<void> init() async {}

  @override
  Future<void> connect(Proxy proxy) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<bool> get connectionStatus => const Stream.empty();

  @override
  Future<double?> testProxy(Proxy proxy,
      {required String testUrl, required Duration timeout}) async {
    final r = calls < results.length ? results[calls] : null;
    calls++;
    return r;
  }
}

Proxy makeProxy(String uri, String server,
    {int port = 443, String protocol = 'Trojan', String? password = 'pw'}) {
  return Proxy(
    protocol: protocol,
    server: server,
    port: port,
    uri: uri,
    password: password,
  );
}

void main() {
  group('ProxyTester.testOne — 3-layer logic', () {
    test('marks working when all 3 layers pass', () async {
      // Local TCP server so layer 1 succeeds deterministically.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      // Accept and immediately close — layer 1 only needs a connection.
      server.listen((socket) => socket.destroy());
      addTearDown(server.close);

      final t = ProxyTester(FakeEngine([100, 120]),
          timeout: const Duration(milliseconds: 900));
      final p = makeProxy('trojan://pw@127.0.0.1:$port', '127.0.0.1', port: port);
      final r = await t.testOne(p);
      expect(r.working, isTrue);
      expect(r.latencyMs, 120);
      expect(r.testType, 'full');
    });

    test('marks failed when TCP unreachable', () async {
      // Port 1 on loopback is effectively closed — layer 1 fails fast.
      final t = ProxyTester(FakeEngine([]),
          timeout: const Duration(milliseconds: 400));
      final p = makeProxy('trojan://pw@127.0.0.1:1', '127.0.0.1', port: 1);
      final r = await t.testOne(p);
      expect(r.working, isFalse);
      expect(r.testType, 'tcp_fail');
    });

    test('marks failed when layer 2 fails', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((socket) => socket.destroy());
      addTearDown(server.close);

      final t = ProxyTester(FakeEngine([null]),
          timeout: const Duration(milliseconds: 900));
      final p = makeProxy('trojan://pw@127.0.0.1:$port', '127.0.0.1', port: port);
      final r = await t.testOne(p);
      expect(r.testType, 'full_fail'); // layer 1 OK, layer 2 failed
      expect(r.working, isFalse);
    });

    test('marks failed when validation (L3) fails', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((socket) => socket.destroy());
      addTearDown(server.close);

      final t = ProxyTester(FakeEngine([100, null]),
          timeout: const Duration(milliseconds: 900));
      final p = makeProxy('trojan://pw@127.0.0.1:$port', '127.0.0.1', port: port);
      final r = await t.testOne(p);
      expect(r.working, isFalse);
      expect(r.latencyMs, 100);
      expect(r.testType, 'validation_fail');
    });
  });

  group('ProxyTester.pickBest', () {
    test('returns fastest working proxy', () {
      final results = [
        makeProxy('a', 'a.com').copyWithResult(working: true, latencyMs: 300, testType: 'full'),
        makeProxy('b', 'b.com').copyWithResult(working: true, latencyMs: 100, testType: 'full'),
        makeProxy('c', 'c.com').copyWithResult(working: false, latencyMs: 50, testType: 'tcp_fail'),
      ];
      final best = ProxyTester.pickBest(results);
      expect(best!.server, 'b.com');
    });

    test('returns null when nothing works', () {
      final results = [
        makeProxy('a', 'a.com').copyWithResult(working: false, testType: 'tcp_fail'),
      ];
      expect(ProxyTester.pickBest(results), isNull);
    });
  });

  group('ProxyTester.sortedForDisplay', () {
    test('working first, then fastest', () {
      final results = [
        makeProxy('slow', 'slow.com').copyWithResult(working: true, latencyMs: 999, testType: 'full'),
        makeProxy('fast', 'fast.com').copyWithResult(working: true, latencyMs: 50, testType: 'full'),
        makeProxy('dead', 'dead.com').copyWithResult(working: false, testType: 'tcp_fail'),
      ];
      final sorted = ProxyTester.sortedForDisplay(results);
      expect(sorted.first.server, 'fast.com');
      expect(sorted.last.server, 'dead.com');
    });
  });

  group('Proxy model', () {
    test('fingerprint stable across copies', () {
      final a = makeProxy('trojan://x@a.com:443', 'a.com');
      final b = a.copyWithResult(working: true, latencyMs: 1, testType: 'full');
      expect(a.fingerprint, b.fingerprint);
    });

    test('JSON round-trip preserves fields', () {
      final p = makeProxy('trojan://pw@a.com:443', 'a.com')
          .copyWithResult(working: true, latencyMs: 100, testType: 'full')
          .copyWithSpeedData(const SpeedData(avgMs: 90, minMs: 80, maxMs: 100, jitterMs: 5, successRate: 100));
      final restored = Proxy.fromJson(p.toJson());
      expect(restored.protocol, p.protocol);
      expect(restored.server, p.server);
      expect(restored.port, p.port);
      expect(restored.uri, p.uri);
      expect(restored.working, isTrue);
      expect(restored.latencyMs, 100);
      expect(restored.speedData!.avgMs, 90);
    });
  });
}