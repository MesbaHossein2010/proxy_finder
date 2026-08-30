/// Mirrors the fields your desktop app's parse_vmess/parse_ss/parse_trojan/
/// parse_vless functions produce, so config generation logic maps 1:1.
class Proxy {
  final String protocol; // 'VMess' | 'Shadowsocks' | 'Trojan' | 'VLESS'
  final String server;
  final int port;
  final String uri;

  // Protocol-specific fields (only the relevant ones are populated per type)
  final String? uuid; // VMess/VLESS id, or SS password
  final String? password; // Trojan password
  final String? encryption; // VMess security / SS cipher method
  final String network; // 'tcp' | 'ws' | 'http' | 'grpc'
  final String? tls; // '' | 'tls' | 'xtls' | 'reality'
  final String? sni;
  final String? path;
  final String? host;

  // Test result state (null/unset until tested)
  final bool? working;
  final double? latencyMs;
  final String? testType; // 'tcp' | 'full' | 'tcp_fail' | 'full_fail' | ...
  final SpeedData? speedData;

  const Proxy({
    required this.protocol,
    required this.server,
    required this.port,
    required this.uri,
    this.uuid,
    this.password,
    this.encryption,
    this.network = 'tcp',
    this.tls,
    this.sni,
    this.path,
    this.host,
    this.working,
    this.latencyMs,
    this.testType,
    this.speedData,
  });

  /// Stable identity for a proxy — server:port:protocol is enough to detect
  /// duplicates across different import sources, even when URIs differ.
  String get fingerprint => '$protocol|$server:$port';

  Proxy copyWithResult({
    required bool working,
    double? latencyMs,
    required String testType,
  }) {
    return Proxy(
      protocol: protocol,
      server: server,
      port: port,
      uri: uri,
      uuid: uuid,
      password: password,
      encryption: encryption,
      network: network,
      tls: tls,
      sni: sni,
      path: path,
      host: host,
      working: working,
      latencyMs: latencyMs,
      testType: testType,
      speedData: speedData,
    );
  }

  Proxy copyWithSpeedData(SpeedData? data) {
    return Proxy(
      protocol: protocol,
      server: server,
      port: port,
      uri: uri,
      uuid: uuid,
      password: password,
      encryption: encryption,
      network: network,
      tls: tls,
      sni: sni,
      path: path,
      host: host,
      working: working,
      latencyMs: latencyMs,
      testType: testType,
      speedData: data,
    );
  }

  /// General-purpose copy with overridable fields (used by filters etc).
  Proxy copyWith({
    String? protocol,
    String? server,
    int? port,
    String? uri,
    String? uuid,
    String? password,
    String? encryption,
    String? network,
    String? tls,
    String? sni,
    String? path,
    String? host,
    bool? working,
    double? latencyMs,
    String? testType,
    SpeedData? speedData,
  }) {
    return Proxy(
      protocol: protocol ?? this.protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      uri: uri ?? this.uri,
      uuid: uuid ?? this.uuid,
      password: password ?? this.password,
      encryption: encryption ?? this.encryption,
      network: network ?? this.network,
      tls: tls ?? this.tls,
      sni: sni ?? this.sni,
      path: path ?? this.path,
      host: host ?? this.host,
      working: working ?? this.working,
      latencyMs: latencyMs ?? this.latencyMs,
      testType: testType ?? this.testType,
      speedData: speedData ?? this.speedData,
    );
  }

  /// JSON for persistence/export (uri kept — it's the canonical form).
  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'server': server,
        'port': port,
        'uri': uri,
        'uuid': uuid,
        'password': password,
        'encryption': encryption,
        'network': network,
        'tls': tls,
        'sni': sni,
        'path': path,
        'host': host,
        'working': working,
        'latencyMs': latencyMs,
        'testType': testType,
        'speedData': speedData?.toJson(),
      };

  factory Proxy.fromJson(Map<String, dynamic> d) => Proxy(
        protocol: d['protocol'] ?? '',
        server: d['server'] ?? '',
        port: (d['port'] ?? 0) as int,
        uri: d['uri'] ?? '',
        uuid: d['uuid'] as String?,
        password: d['password'] as String?,
        encryption: d['encryption'] as String?,
        network: d['network'] ?? 'tcp',
        tls: d['tls'] as String?,
        sni: d['sni'] as String?,
        path: d['path'] as String?,
        host: d['host'] as String?,
        working: d['working'] as bool?,
        latencyMs: (d['latencyMs'] as num?)?.toDouble(),
        testType: d['testType'] as String?,
        speedData: d['speedData'] != null
            ? SpeedData.fromJson(d['speedData'] as Map<String, dynamic>)
            : null,
      );
}

/// Port of desktop's speed test result dict (avg/min/max/jitter/success_rate).
class SpeedData {
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double jitterMs;
  final double successRate; // 0-100

  const SpeedData({
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.jitterMs,
    required this.successRate,
  });

  Map<String, dynamic> toJson() => {
        'avgMs': avgMs,
        'minMs': minMs,
        'maxMs': maxMs,
        'jitterMs': jitterMs,
        'successRate': successRate,
      };

  factory SpeedData.fromJson(Map<String, dynamic> d) => SpeedData(
        avgMs: (d['avgMs'] as num).toDouble(),
        minMs: (d['minMs'] as num).toDouble(),
        maxMs: (d['maxMs'] as num).toDouble(),
        jitterMs: (d['jitterMs'] as num).toDouble(),
        successRate: (d['successRate'] as num).toDouble(),
      );

  String get summary =>
      'avg ${avgMs.toStringAsFixed(0)}ms · min ${minMs.toStringAsFixed(0)}ms · '
      'max ${maxMs.toStringAsFixed(0)}ms · jitter ${jitterMs.toStringAsFixed(0)}ms · '
      '${successRate.toStringAsFixed(0)}% ok';
}