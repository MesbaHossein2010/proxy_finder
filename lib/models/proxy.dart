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
  });

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
    );
  }
}
