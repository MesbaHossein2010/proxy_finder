import 'dart:convert';

import 'package:mmkv/mmkv.dart';
import 'models/proxy.dart';

/// Persistent store for imported proxies and last test results.
/// Backed by MMKV — lightweight, synchronous, no async boilerplate.
class ProxyStore {
  static const _kProxies = 'imported_proxies';
  static const _kResults = 'last_results';

  static MMKV? _box;
  static Future<void>? _initFuture;

  /// Kick off (and cache) MMKV initialisation. The future is stored so the
  /// UI never awaits it — a failure here (e.g. missing native lib in widget
  /// tests) must never crash the app, so it is swallowed and box stays null.
  static Future<void> _ensureInit() {
    return _initFuture ??= () async {
      try {
        await MMKV.initialize();
        _box = MMKV.defaultMMKV();
      } catch (_) {
        _box = null;
      }
    }();
  }

  static bool get _available => _box != null;

  /// Non-blocking warm-up; call once at startup.
  static Future<void> warmUp() => _ensureInit();

  /// Save the full imported list so it survives app restarts.
  static void saveProxies(List<Proxy> proxies) {
    if (!_available) return;
    final json = jsonEncode(proxies.map((p) => p.toJson()).toList());
    _box!.encodeString(_kProxies, json);
  }

  static List<Proxy> loadProxies() {
    if (!_available) return [];
    final raw = _box!.decodeString(_kProxies);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Proxy.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save last test results (with latency/speed data) for quick re-view.
  static void saveResults(List<Proxy> results) {
    if (!_available) return;
    final json = jsonEncode(results.map((p) => p.toJson()).toList());
    _box!.encodeString(_kResults, json);
  }

  static List<Proxy> loadResults() {
    if (!_available) return [];
    final raw = _box!.decodeString(_kResults);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Proxy.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void clearResults() {
    if (_available) _box!.removeValue(_kResults);
  }
}

/// Export helpers — turn a list of tested proxies into a shareable string.
class ResultExporter {
  /// Builds a clean text export: one line per proxy with status + latency.
  static String toText(List<Proxy> results) {
    final lines = <String>[];
    for (final p in ProxyTesterSorted.results(results)) {
      final status = p.working == true ? 'OK' : 'FAIL';
      final lat = p.latencyMs != null ? '${p.latencyMs!.toStringAsFixed(0)}ms' : '-';
      lines.add('[$status] $lat  ${p.protocol}  ${p.server}:${p.port}');
    }
    return lines.join('\n');
  }

  /// Exports only working URIs (one per line) — ready to paste elsewhere.
  static String workingUris(List<Proxy> results) {
    return results
        .where((p) => p.working == true)
        .map((p) => p.uri)
        .join('\n');
  }
}

/// Thin wrapper so ResultExporter can reuse the sorted-for-display logic
/// without re-importing the whole tester.
class ProxyTesterSorted {
  static List<Proxy> results(List<Proxy> tested) {
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
}
