import 'dart:async';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'models/proxy.dart';

/// Real testing engine backed by flutter_sing_box.
///
/// NOT YET VALIDATED ON A REAL DEVICE. Built from reading the plugin's
/// actual source (clash-sing/flutter_sing_box on GitHub), not just its
/// docs, but the only way to confirm it truly works is running it and
/// watching real behavior/logs. If your phone's normal internet breaks
/// while testing runs, the route.final = direct-out setting below is
/// the first thing to check.
///
/// Architecture: rather than testing proxies one at a time (which would
/// mean toggling the system VPN per proxy — bad), all candidates are
/// added as members of one shared "urltest" group. Android's VPN
/// permission prompt appears once, the group is tested together via the
/// plugin's real urlTest() call, and results come back per-proxy through
/// groupStream as urlTestDelay (0 = failed, >0ms = real measured latency).
class SingBoxTestEngine {
  final _fsb = FlutterSingBox();
  final _statusController = StreamController<bool>.broadcast();
  bool _vpnStarted = false;

  static const _groupTag = 'test-group';
  static const _directTag = 'direct-out';
  static const _tunTag = 'tun-in';

  Future<void> init() async {
    await _fsb.init();
  }

  String tagFor(Proxy p) => 'p${p.uri.hashCode}';

  Outbound _buildOutbound(Proxy p) {
    Tls? tls;
    if ((p.tls ?? '').isNotEmpty) {
      tls = Tls(enabled: true, insecure: true, serverName: p.sni ?? p.server);
    }

    Transport? transport;
    if (p.network == 'ws') {
      transport = Transport(type: 'ws', path: p.path ?? '/', headers: {'Host': p.host ?? p.server});
    } else if (p.network == 'grpc') {
      // Model has no dedicated grpc serviceName field — reusing `path`.
      transport = Transport(type: 'grpc', path: (p.path ?? '').replaceFirst('/', ''));
    } else if (p.network == 'http') {
      transport = Transport(type: 'http', path: p.path ?? '/', headers: {'Host': p.host ?? p.server});
    }

    final type = switch (p.protocol) {
      'VMess' => 'vmess',
      'VLESS' => 'vless',
      'Trojan' => 'trojan',
      'Shadowsocks' => 'shadowsocks',
      _ => 'direct',
    };

    return Outbound(
      tag: tagFor(p),
      type: type,
      server: p.server,
      serverPort: p.port,
      uuid: (p.protocol == 'VMess' || p.protocol == 'VLESS') ? p.uuid : null,
      password: p.protocol == 'Trojan' ? p.password : (p.protocol == 'Shadowsocks' ? p.uuid : null),
      method: p.protocol == 'Shadowsocks' ? p.encryption : null,
      security: p.protocol == 'VMess' ? (p.encryption ?? 'auto') : null,
      alterId: p.protocol == 'VMess' ? 0 : null,
      tls: tls,
      transport: transport,
    );
  }

  Future<void> _activateProfileWithGroup(List<Proxy> proxies) async {
    final proxyOutbounds = proxies.map(_buildOutbound).toList();
    final memberTags = proxyOutbounds.map((o) => o.tag).toList();

    final groupOutbound = Outbound(
      tag: _groupTag,
      type: 'urltest',
      outbounds: memberTags,
      url: 'http://www.gstatic.com/generate_204',
      interval: '5m',
      tolerance: 50,
    );

    final directOutbound = Outbound(tag: _directTag, type: 'direct');

    final tunInbound = Inbound(
      tag: _tunTag,
      type: 'tun',
      interfaceName: 'tun0',
      address: ['172.19.0.1/28'],
      mtu: 1500,
      autoRoute: true,
      strictRoute: false,
      stack: 'system',
    );

    final config = SingBox(
      dns: Dns(servers: [Server(tag: 'dns-out', type: 'udp', server: '8.8.8.8')], rules: []),
      inbounds: [tunInbound],
      route: Route(
        rules: [],
        autoDetectInterface: true,
        // Everything not explicitly routed goes DIRECT — your phone's
        // real traffic should keep working while proxies are tested.
        routeFinal: _directTag,
      ),
      outbounds: [groupOutbound, directOutbound, ...proxyOutbounds],
    );

    final storage = ProfileStorage();
    final existing = storage.getSelectedProfile();
    final int id = existing?.id ?? storage.generateProfileId;
    final path = await storage.getProfilePath(id);
    final Profile profile = existing ??
        Profile(
          id: id,
          order: 0,
          name: 'proxy-checker-test',
          outboundsCount: null,
          typed: TypedProfile(
            type: ProfileType.local,
            path: path,
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await storage.addProfile(profile, config);
    storage.setSelectedProfile(id);
  }

  /// Tests every proxy in one shot via the shared urltest group. Returns
  /// a map of proxy tag -> latency in ms (null = failed).
  Future<Map<String, double?>> testGroup(
    List<Proxy> proxies, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    await _activateProfileWithGroup(proxies);

    if (!_vpnStarted) {
      await _fsb.startVpn();
      _vpnStarted = true;
      _statusController.add(true);
    } else {
      await _fsb.serviceReload();
    }

    final completer = Completer<Map<String, double?>>();
    late final StreamSubscription sub;
    final expectedTags = proxies.map(tagFor).toSet();

    sub = _fsb.groupStream.listen((groups) {
      ClientGroup? group;
      for (final g in groups) {
        if (g.tag == _groupTag) group = g;
      }
      if (group == null) return;
      final items = group.items ?? [];
      final tested = items.where((i) => expectedTags.contains(i.tag));
      final allDone = tested.length == expectedTags.length && tested.every((i) => i.urlTestTime > 0);
      if (allDone) {
        final results = <String, double?>{
          for (final item in tested) item.tag: (item.urlTestDelay > 0 ? item.urlTestDelay.toDouble() : null),
        };
        if (!completer.isCompleted) completer.complete(results);
      }
    });

    await _fsb.urlTest(groupTag: _groupTag);

    final results = await completer.future.timeout(
      timeout,
      onTimeout: () => {for (final t in expectedTags) t: null},
    );
    await sub.cancel();
    return results;
  }

  Future<void> shutdown() async {
    if (_vpnStarted) {
      await _fsb.stopVpn();
      _vpnStarted = false;
      _statusController.add(false);
    }
  }

  Stream<bool> get connectionStatus => _statusController.stream;
}
