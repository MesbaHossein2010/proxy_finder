import 'dart:async';
import 'dart:math';
import 'models/proxy.dart';
import 'proxy_engine.dart';

/// Fake engine so you can build/test the UI and test-loop logic locally
/// (flutter run -d linux) before wiring in a real plugin, which only runs
/// on Android. Swap this for the real implementation in main.dart once
/// you've picked and vetted a plugin.
class MockEngine implements ProxyEngine {
  final _statusController = StreamController<bool>.broadcast();
  final _rand = Random();

  @override
  Future<void> init() async {}

  @override
  Future<double?> testProxy(Proxy proxy, {required String testUrl, required Duration timeout}) async {
    await Future.delayed(Duration(milliseconds: 200 + _rand.nextInt(600)));
    final fails = _rand.nextDouble() < 0.35;
    if (fails) return null;
    return 50 + _rand.nextDouble() * 400;
  }

  @override
  Future<void> connect(Proxy proxy) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _statusController.add(true);
  }

  @override
  Future<void> disconnect() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _statusController.add(false);
  }

  @override
  Stream<bool> get connectionStatus => _statusController.stream;
}
