import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/services.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:path/path.dart' as p;
import 'models/proxy.dart';
import 'proxy_engine.dart';

/// Real testing engine backed by flutter_sing_box.
///
/// Architecture: rather than testing proxies one at a time (which would
/// mean toggling the system VPN per proxy — bad), all candidates are
/// added as members of one shared "urltest" group. Android's VPN
/// permission prompt appears once, the group is tested together via the
/// plugin's real urlTest() call, and results come back per-proxy through
/// groupStream as urlTestDelay (0 = failed, >0ms = real measured latency).
class SingBoxTestEngine implements ProxyEngine {
  final _fsb = FlutterSingBox();
  final _statusController = StreamController<bool>.broadcast();
  bool _vpnStarted = false;
  bool _initialised = false;

  static const _groupTag = 'test-group';
  static const _directTag = 'direct-out';
  static const _tunTag = 'tun-in';

  /// One-time init, safe to call repeatedly. Never hangs: the plugin now
  /// answers immediately and binds its service in the background.
  Future<void> init() async {
    if (_initialised) return;
    await _fsb.init();
    _initialised = true;
  }

  /// Check if VPN permission is already granted. Returns true if permission
  /// is already granted (no system dialog needed), false if the app must
  /// request it via startVpn() which triggers the system dialog.
  Future<bool> isVpnPermissionGranted() async {
    try {
      await init();
      return await _fsb.prepareVpn();
    } catch (_) {
      return false;
    }
  }

  /// Start the VPN tunnel (requests system permission if not yet granted).
  /// Returns true if VPN started successfully, false if user denied or
  /// dialog timed out. Rethrows unexpected errors.
  Future<bool> startVpn() async {
    try {
      await _fsb.startVpn();
      _vpnStarted = true;
      _statusController.add(true);
      return true;
    } catch (e) {
      final msg = e.toString();
      // User-facing errors that should return false (not crash):
      if (msg.contains('VPN_PERMISSION_DENIED') ||
          msg.contains('ALREADY_WAITING') ||
          msg.contains('NO_ACTIVITY') ||
          msg.contains('PLUGIN_NOT_INIT')) {
        return false;
      }
      rethrow;
    }
  }

  bool get isInitialised => _initialised;
  bool get isVpnStarted => _vpnStarted;

  /// Reports the sing-box core version, for diagnostics.
  Future<String> version() async {
    try {
      return await _fsb.getSingBoxVersion();
    } catch (_) {
      return 'unknown';
    }
  }

  /// ProxyEngine implementation — tests a single proxy through the shared
  /// urltest group and returns its latency in ms (null = failed).
  @override
  Future<double?> testProxy(Proxy proxy,
      {required String testUrl, required Duration timeout}) async {
    try {
      final results = await testGroup([proxy], timeout: timeout);
      return results[tagFor(proxy)];
    } catch (_) {
      return null;
    }
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
      password: p.protocol == 'Trojan'
          ? p.password
          : (p.protocol == 'Shadowsocks' ? p.uuid : null),
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

    // Native BoxService reads its active config from the path stored under
    // the "using_config" MMKV key (see ProfileManager.getUsingConfig() on
    // the Kotlin side) — addProfile() above only writes profiles/<id>.json,
    // it never sets that key or writes using_config.json. Without this,
    // the native side finds no config, hits EmptyConfiguration, and
    // self-stops (commandServer.close() + service.stopSelf()), closing the
    // command socket every time — including on every restart.
    final documentsDir = await storage.getStorageDirectory();
    final usingConfigFile = io.File(p.join(documentsDir.path, 'using_config.json'));
    await usingConfigFile.writeAsString(jsonEncode(config.toJson()));
    storage.setUsingConfig(documentsDir.path);
  }

  /// Runs [call], restarting the VPN and retrying once if it fails because
  /// the background command socket is gone (the service was killed by the OS
  /// — common on HyperOS/MIUI).
  ///
  /// Only dead-service (dial-level) errors trigger the restart. Real
  /// config, protocol or permission errors surface unchanged — they must
  /// never be masked by a silent restart. The retry happens at most once;
  /// if the call still fails afterwards, the error propagates.
  Future<void> _withDeadServiceRecovery(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (e) {
      if (!_isDeadServiceMessage(e.message ?? '')) rethrow;

      // The command socket is gone, so the service really is dead. Restart
      // the VPN and give it ~500ms to bind before retrying the call once.
      final started = await startVpn();
      if (!started) {
        throw Exception('VPN permission denied. Grant VPN permission and try again.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Wait for the command socket to actually exist before retrying —
      // startVpn() returning success only means the Android service start
      // call succeeded, not that the Go runtime has bound the socket yet.
      await _waitForCommandSocket();
      await call();
    }
  }

  /// True when [msg] points to a dead/missing command socket (a dial-level
  /// failure) rather than a real config, protocol or permission error.
  bool _isDeadServiceMessage(String msg) {
    return msg.contains('no such file or directory') ||
        msg.contains('DeadlineExceeded') ||
        msg.contains('connection error') ||
        msg.contains('broken pipe') ||
        msg.contains('connection refused') ||
        msg.contains('EOF');
  }

  /// Polls for the command socket to be ready before a retry. Uses the
  /// native isCommandSocketReady probe (checks the real socket file that
  /// urlTest/serviceReload dial) with a bounded window so we never hang.
  Future<void> _waitForCommandSocket({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    do {
      try {
        if (await _fsb.isCommandSocketReady()) return;
      } catch (_) {
        // Probe itself failed — keep polling until the deadline.
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } while (DateTime.now().isBefore(deadline));
  }

  /// Tests every proxy in one shot via the shared urltest group. Returns
  /// a map of proxy tag -> latency in ms (null = failed).
  Future<Map<String, double?>> testGroup(
    List<Proxy> proxies, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (proxies.isEmpty) return {};
    await init();
    await _activateProfileWithGroup(proxies);

    // Track why we're in this branch, not just the boolean (Claude's design):
    // if the VPN service was just started in THIS testGroup call, skip
    // serviceReload entirely — it is redundant work and races the socket
    // bind. Only reload when reusing a service started in a PRIOR call.
    if (!_vpnStarted) {
      final started = await startVpn();
      if (!started) {
        throw Exception('VPN permission denied. Grant VPN permission and try again.');
      }
      // startVpn() sets _vpnStarted = true on success.
      // Fresh start: wait for the command socket to bind before urlTest.
      await _waitForCommandSocket();
    } else {
      // Cheap local check — no dial, no timeout — before assuming the
      // service is alive. serviceReload only makes sense against a socket
      // that actually exists; retrying it against a dead one just wastes
      // the RPC's DeadlineExceeded timeout before recovery even starts.
      if (await _fsb.isCommandSocketReady()) {
        await _withDeadServiceRecovery(_fsb.serviceReload);
      } else {
        // Socket's already gone — treat exactly like a fresh start.
        // _activateProfileWithGroup already ran above, so config is in place.
        final started = await startVpn();
        if (!started) {
          throw Exception('VPN permission denied. Grant VPN permission and try again.');
        }
        await _waitForCommandSocket();
      }
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
      // urlTestTime > 0 means the test completed for that item (pass OR fail).
      // We wait until ALL expected items have completed their test.
      final allDone = tested.length == expectedTags.length && tested.every((i) => i.urlTestTime > 0);
      if (allDone) {
        final results = <String, double?>{
          for (final item in tested)
            item.tag: (item.urlTestDelay > 0 ? item.urlTestDelay.toDouble() : null),
        };
        if (!completer.isCompleted) completer.complete(results);
      }
    });

    // Test the group. If the background service died, the command socket is
    // gone and this call throws; _withDeadServiceRecovery restarts the VPN
    // and retries once before letting the error propagate.
    await _withDeadServiceRecovery(() => _fsb.urlTest(groupTag: _groupTag));

    final results = await completer.future.timeout(
      timeout,
      onTimeout: () => {for (final t in expectedTags) t: null},
    );
    await sub.cancel();
    return results;
  }

  /// Connects the system VPN using the winning proxy (selects it in the
  /// urltest group, then ensures the VPN service is running).
  Future<void> connect(Proxy proxy) async {
    await init();
    try {
      await _fsb.selectOutbound(groupTag: _groupTag, outboundTag: tagFor(proxy));
    } catch (_) {
      // group may not be active yet — profile activation is done by testGroup
    }
    if (!_vpnStarted) {
      final started = await startVpn();
      if (!started) {
        throw Exception('VPN permission denied. Grant VPN permission and try again.');
      }
    }
    _statusController.add(true);
  }

  Future<void> disconnect() async {
    if (_vpnStarted) {
      await _fsb.stopVpn();
      _vpnStarted = false;
      _statusController.add(false);
    }
  }

  Future<void> shutdown() => disconnect();

  Stream<bool> get connectionStatus => _statusController.stream;
}