import 'dart:convert';
import 'models/proxy.dart';

const _proxySchemes = ['vmess://', 'ss://', 'trojan://', 'vless://'];

/// Dart's base64 decoder is strict about padding, unlike Python's, which
/// silently tolerates missing '='. This restores the padding manually,
/// matching desktop's `e += "=" * p` logic.
String _padBase64(String input) {
  final mod = input.length % 4;
  if (mod == 0) return input;
  return input + '=' * (4 - mod);
}

/// Port of extract_proxy_uris: pulls proxy URIs out of pasted/imported text,
/// including base64-encoded subscription blobs.
List<String> extractProxyUris(String text) {
  final uris = <String>[];
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;

    final looksLikeUri = _proxySchemes.any((s) => line.startsWith(s));
    if (!looksLikeUri) {
      // Try treating the whole line as base64-encoded subscription content
      try {
        final decoded = utf8.decode(base64.decode(_padBase64(line)));
        if (_proxySchemes.any((s) => decoded.contains(s))) {
          uris.addAll(extractProxyUris(decoded));
          continue;
        }
      } catch (_) {
        // not base64, fall through
      }
    }

    if (line.contains('|') && _proxySchemes.any((s) => line.contains(s))) {
      for (final part in line.split('|')) {
        final p = part.trim();
        if (_proxySchemes.any((s) => p.startsWith(s))) uris.add(p);
      }
    } else if (_proxySchemes.any((s) => line.startsWith(s))) {
      uris.add(line);
    }
  }

  return uris.toSet().toList(); // de-dupe, same as desktop's seen/unique logic
}

Proxy? parseProxyUri(String uri) {
  uri = uri.trim();
  if (uri.startsWith('vmess://')) return _parseVmess(uri);
  if (uri.startsWith('ss://')) return _parseSs(uri);
  if (uri.startsWith('trojan://')) return _parseTrojan(uri);
  if (uri.startsWith('vless://')) return _parseVless(uri);
  return null;
}

/// Port of parse_vmess: base64 JSON blob after "vmess://"
Proxy? _parseVmess(String uri) {
  try {
    final decoded = utf8.decode(base64.decode(_padBase64(uri.substring(8))));
    final d = jsonDecode(decoded) as Map<String, dynamic>;
    return Proxy(
      protocol: 'VMess',
      server: d['add'] ?? '',
      port: int.tryParse('${d['port'] ?? 0}') ?? 0,
      uuid: d['id'] ?? '',
      encryption: d['scy'] ?? d['security'] ?? 'auto',
      network: d['net'] ?? 'tcp',
      tls: d['tls'] ?? '',
      sni: d['sni'] ?? d['host'] ?? '',
      path: d['path'] ?? '/',
      host: d['host'] ?? '',
      uri: uri,
    );
  } catch (_) {
    return null;
  }
}

/// Port of parse_ss: handles both "method:pass@host:port" and the fully
/// base64-encoded "ss://<base64>" legacy form.
Proxy? _parseSs(String uri) {
  try {
    var rest = uri.substring(5);
    final hashIdx = rest.indexOf('#');
    if (hashIdx != -1) rest = rest.substring(0, hashIdx);

    String userInfo, hostPort;
    if (rest.contains('@')) {
      final atIdx = rest.lastIndexOf('@');
      userInfo = rest.substring(0, atIdx);
      hostPort = rest.substring(atIdx + 1);
    } else {
      final decoded = utf8.decode(base64.decode(_padBase64(rest)));
      final atIdx = decoded.lastIndexOf('@');
      userInfo = decoded.substring(0, atIdx);
      hostPort = decoded.substring(atIdx + 1);
    }

    final colonIdx = userInfo.indexOf(':');
    final method = userInfo.substring(0, colonIdx);
    final pass = userInfo.substring(colonIdx + 1);
    final hpColonIdx = hostPort.lastIndexOf(':');
    final host = hostPort.substring(0, hpColonIdx);
    final port = int.parse(hostPort.substring(hpColonIdx + 1));

    return Proxy(
      protocol: 'Shadowsocks',
      server: host,
      port: port,
      encryption: method,
      uuid: pass, // password, reusing the "uuid" slot like desktop does
      uri: uri,
    );
  } catch (_) {
    return null;
  }
}

/// Port of parse_trojan: standard URI with query params for sni/type/path/host
Proxy? _parseTrojan(String uri) {
  try {
    final u = Uri.parse(uri);
    return Proxy(
      protocol: 'Trojan',
      server: u.host,
      port: u.hasPort ? u.port : 443,
      password: u.userInfo,
      sni: u.queryParameters['sni'] ?? u.host,
      tls: u.queryParameters['security'] ?? 'tls',
      network: u.queryParameters['type'] ?? 'tcp',
      path: Uri.decodeComponent(u.queryParameters['path'] ?? '/'),
      host: u.queryParameters['host'] ?? u.host,
      uri: uri,
    );
  } catch (_) {
    return null;
  }
}

/// Port of parse_vless: same URI shape as Trojan but with uuid instead of password
Proxy? _parseVless(String uri) {
  try {
    final u = Uri.parse(uri);
    return Proxy(
      protocol: 'VLESS',
      server: u.host,
      port: u.hasPort ? u.port : 443,
      uuid: u.userInfo,
      encryption: u.queryParameters['encryption'] ?? 'none',
      network: u.queryParameters['type'] ?? 'tcp',
      tls: u.queryParameters['security'] ?? '',
      sni: u.queryParameters['sni'] ?? u.host,
      path: u.queryParameters['path'] ?? '/',
      host: u.queryParameters['host'] ?? '',
      uri: uri,
    );
  } catch (_) {
    return null;
  }
}
