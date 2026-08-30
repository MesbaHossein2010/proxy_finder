import 'dart:convert';
import 'models/proxy.dart';

const _proxySchemes = ['vmess://', 'ss://', 'trojan://', 'vless://'];
const _validProtocols = {'VMess', 'Shadowsocks', 'Trojan', 'VLESS'};

/// Dart's base64 decoder is strict about padding, unlike Python's, which
/// silently tolerates missing '='. This restores the padding manually,
/// matching desktop's `e += "=" * p` logic.
String _padBase64(String input) {
  final mod = input.length % 4;
  if (mod == 0) return input;
  return input + '=' * (4 - mod);
}

/// Removes non-base64 characters that commonly sneak into subscription blobs
/// (whitespace, inline comments, fragments).
String _sanitizeBase64(String input) {
  return input.replaceAll(RegExp(r'\s'), '');
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
        final cleaned = _sanitizeBase64(line);
        if (cleaned.length < 8) continue;
        final decoded = utf8.decode(base64.decode(_padBase64(cleaned)));
        if (_proxySchemes.any((s) => decoded.contains(s))) {
          uris.addAll(extractProxyUris(decoded));
          continue;
        }
      } catch (_) {
        // not base64, fall through
      }
    }

    if (line.contains('|') && _proxySchemes.any((s) => line.contains(s))) {
      // Clash-style "|"-separated lists may mix several schemes
      for (final part in line.split('|')) {
        final p = part.trim();
        if (_proxySchemes.any((s) => p.startsWith(s))) uris.add(p);
      }
    } else if (_proxySchemes.any((s) => line.startsWith(s))) {
      uris.add(line);
    } else {
      // Embedded URI inside a larger line (e.g. markup, logs)
      final embedded = RegExp(r'(vmess|ss|trojan|vless)://[^\s<>"]+')
          .firstMatch(line)
          ?.group(0);
      if (embedded != null) uris.add(embedded);
    }
  }

  return uris.toSet().toList(); // de-dupe, same as desktop's seen/unique logic
}

/// Validate that a parsed proxy has a usable server/port.
bool _isValidProxy(Proxy? p) {
  if (p == null) return false;
  if (!_validProtocols.contains(p.protocol)) return false;
  if (p.server.isEmpty) return false;
  if (p.port <= 0 || p.port > 65535) return false;
  // Basic sanity: password/uuid should be non-trivial
  if (p.protocol == 'Trojan' && (p.password == null || p.password!.isEmpty)) {
    return false;
  }
  if ((p.protocol == 'VMess' || p.protocol == 'VLESS') &&
      (p.uuid == null || p.uuid!.length < 8)) {
    return false;
  }
  return true;
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
    final decoded = utf8.decode(base64.decode(_padBase64(_sanitizeBase64(uri.substring(8)))));
    final d = jsonDecode(decoded) as Map<String, dynamic>;
    final proxy = Proxy(
      protocol: 'VMess',
      server: (d['add'] ?? '').toString(),
      port: int.tryParse('${d['port'] ?? 0}') ?? 0,
      uuid: (d['id'] ?? '').toString(),
      encryption: (d['scy'] ?? d['security'] ?? 'auto').toString(),
      network: (d['net'] ?? 'tcp').toString(),
      tls: (d['tls'] ?? '').toString(),
      sni: (d['sni'] ?? d['host'] ?? '').toString(),
      path: (d['path'] ?? '/').toString(),
      host: (d['host'] ?? '').toString(),
      uri: uri,
    );
    return _isValidProxy(proxy) ? proxy : null;
  } catch (_) {
    return null;
  }
}

/// Port of parse_ss: handles both "method:pass@host:port" and the fully
/// base64-encoded "ss://<base64>" legacy form, plus the modern SIP002
/// "ss://<base64 method:pass>@host:port" form.
Proxy? _parseSs(String uri) {
  try {
    var rest = uri.substring(5);
    final hashIdx = rest.indexOf('#');
    if (hashIdx != -1) rest = rest.substring(0, hashIdx);

    String userInfo, hostPort;
    if (rest.contains('@')) {
      // SIP002: userinfo may itself be base64 ("<b64>@host:port")
      final atIdx = rest.lastIndexOf('@');
      final rawUser = rest.substring(0, atIdx);
      hostPort = rest.substring(atIdx + 1);
      if (rawUser.contains(':')) {
        userInfo = rawUser;
      } else {
        // base64-encoded method:pass
        userInfo = utf8.decode(base64.decode(_padBase64(_sanitizeBase64(rawUser))));
      }
    } else {
      final decoded = utf8.decode(base64.decode(_padBase64(_sanitizeBase64(rest))));
      final atIdx = decoded.lastIndexOf('@');
      if (atIdx == -1) return null;
      userInfo = decoded.substring(0, atIdx);
      hostPort = decoded.substring(atIdx + 1);
    }

    final colonIdx = userInfo.indexOf(':');
    if (colonIdx <= 0) return null;
    final method = userInfo.substring(0, colonIdx);
    final pass = userInfo.substring(colonIdx + 1);
    if (pass.isEmpty) return null;

    final hpColonIdx = hostPort.lastIndexOf(':');
    if (hpColonIdx <= 0) return null;
    final host = hostPort.substring(0, hpColonIdx);
    final port = int.tryParse(hostPort.substring(hpColonIdx + 1));
    if (port == null || port <= 0 || port > 65535) return null;

    // Plugin support: "plugin=obfs-local;obfs=http;obfs-host=..."
    String? plugin;
    final pluginIdx = hostPort.indexOf('?plugin=');
    if (pluginIdx != -1) {
      plugin = hostPort.substring(pluginIdx + 8);
      // plugin is URI-encoded in SIP002
      try {
        plugin = Uri.decodeComponent(plugin);
      } catch (_) {}
    }

    final proxy = Proxy(
      protocol: 'Shadowsocks',
      server: host,
      port: port,
      encryption: method,
      uuid: pass, // password, reusing the "uuid" slot like desktop does
      tls: plugin != null ? 'plugin' : null,
      host: plugin != null ? plugin : null,
      uri: uri,
    );
    return _isValidProxy(proxy) ? proxy : null;
  } catch (_) {
    return null;
  }
}

/// Port of parse_trojan: standard URI with query params for sni/type/path/host
Proxy? _parseTrojan(String uri) {
  try {
    final u = Uri.parse(uri);
    if (u.host.isEmpty || u.userInfo.isEmpty) return null;
    final proxy = Proxy(
      protocol: 'Trojan',
      server: u.host,
      port: u.hasPort ? u.port : 443,
      password: Uri.decodeComponent(u.userInfo),
      sni: u.queryParameters['sni'] ?? u.host,
      tls: u.queryParameters['security'] ?? 'tls',
      network: u.queryParameters['type'] ?? 'tcp',
      path: Uri.decodeComponent(u.queryParameters['path'] ?? '/'),
      host: u.queryParameters['host'] ?? u.host,
      uri: uri,
    );
    return _isValidProxy(proxy) ? proxy : null;
  } catch (_) {
    return null;
  }
}

/// Port of parse_vless: same URI shape as Trojan but with uuid instead of password
Proxy? _parseVless(String uri) {
  try {
    final u = Uri.parse(uri);
    if (u.host.isEmpty || u.userInfo.isEmpty) return null;
    final proxy = Proxy(
      protocol: 'VLESS',
      server: u.host,
      port: u.hasPort ? u.port : 443,
      uuid: Uri.decodeComponent(u.userInfo),
      encryption: u.queryParameters['encryption'] ?? 'none',
      network: u.queryParameters['type'] ?? 'tcp',
      tls: u.queryParameters['security'] ?? '',
      sni: u.queryParameters['sni'] ?? u.host,
      path: u.queryParameters['path'] ?? '/',
      host: u.queryParameters['host'] ?? '',
      uri: uri,
    );
    return _isValidProxy(proxy) ? proxy : null;
  } catch (_) {
    return null;
  }
}