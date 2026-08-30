import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:proxy_checker_mobile/proxy_parser.dart';

void main() {
  group('extractProxyUris', () {
    test('extracts simple vmess URI', () {
      final uris = extractProxyUris('vmess://abc');
      expect(uris, ['vmess://abc']);
    });

    test('extracts multiple URIs from lines', () {
      final text = 'vmess://aaa\ntrojan://bbb@c:443\nvless://ddd';
      final uris = extractProxyUris(text);
      expect(uris.length, 3);
    });

    test('decodes base64 subscription blob', () {
      final blob = base64Encode(utf8.encode('vmess://abc\ntrojan://x@y:443'));
      final uris = extractProxyUris(blob);
      expect(uris.length, 2);
    });

    test('dedupes identical URIs', () {
      final uris = extractProxyUris('vmess://abc\nvmess://abc');
      expect(uris.length, 1);
    });

    test('extracts from pipe-separated line', () {
      final uris = extractProxyUris('vmess://a|ss://b@c:1|trojan://d@e:2');
      expect(uris.length, 3);
    });

    test('extracts embedded URI from noisy line', () {
      final uris = extractProxyUris('some text then vless://x@y:443 more');
      expect(uris, ['vless://x@y:443']);
    });

    test('ignores garbage text', () {
      final uris = extractProxyUris('just plain text\nno proxies here');
      expect(uris, isEmpty);
    });
  });

  group('parseProxyUri', () {
    test('parses valid vmess', () {
      final json = jsonEncode({
        'v': '2', 'ps': 'x', 'add': '1.2.3.4', 'port': '8080',
        'id': '12345678-1234-1234-1234-123456789abc', 'scy': 'auto', 'net': 'ws',
        'path': '/x', 'host': 'h.x', 'tls': 'tls',
      });
      final uri = 'vmess://${base64Encode(utf8.encode(json))}';
      final p = parseProxyUri(uri);
      expect(p, isNotNull);
      expect(p!.server, '1.2.3.4');
      expect(p.port, 8080);
      expect(p.protocol, 'VMess');
      expect(p.network, 'ws');
      expect(p.tls, 'tls');
    });

    test('rejects vmess with bad port', () {
      final json = jsonEncode({'add': '1.2.3.4', 'port': 'notaport', 'id': 'x'});
      final uri = 'vmess://${base64Encode(utf8.encode(json))}';
      expect(parseProxyUri(uri), isNull);
    });

    test('parses ss with password', () {
      final p = parseProxyUri('ss://aes-256-gcm:pass@1.2.3.4:8388');
      expect(p, isNotNull);
      expect(p!.protocol, 'Shadowsocks');
      expect(p.server, '1.2.3.4');
      expect(p.port, 8388);
      expect(p.encryption, 'aes-256-gcm');
    });

    test('parses ss base64 userinfo form', () {
      final userinfo = base64Encode(utf8.encode('aes-256-gcm:pass'));
      final p = parseProxyUri('ss://$userinfo@1.2.3.4:8388');
      expect(p, isNotNull);
      expect(p!.encryption, 'aes-256-gcm');
    });

    test('parses trojan with defaults', () {
      final p = parseProxyUri('trojan://pw@1.2.3.4:443');
      expect(p, isNotNull);
      expect(p!.protocol, 'Trojan');
      expect(p.password, 'pw');
      expect(p.port, 443);
      expect(p.tls, 'tls');
      expect(p.sni, '1.2.3.4');
    });

    test('parses vless with query params', () {
      final p = parseProxyUri('vless://abcdef12-3456-7890-abcd-ef1234567890@1.2.3.4:443?security=tls&type=ws&path=%2Fx&sni=x.com');
      expect(p, isNotNull);
      expect(p!.protocol, 'VLESS');
      expect(p.uuid, 'abcdef12-3456-7890-abcd-ef1234567890');
      expect(p.encryption, 'none');
      expect(p.network, 'ws');
      expect(p.path, '/x');
      expect(p.sni, 'x.com');
    });

    test('rejects unsupported scheme', () {
      expect(parseProxyUri('https://example.com'), isNull);
    });

    test('rejects empty host', () {
      expect(parseProxyUri('trojan://pw@:443'), isNull);
    });

    test('rejects empty password', () {
      expect(parseProxyUri('trojan://@1.2.3.4:443'), isNull);
    });

    test('rejects invalid port range', () {
      expect(parseProxyUri('ss://aes-256-gcm:p@1.2.3.4:99999'), isNull);
    });
  });
}