import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:mmkv/mmkv.dart';
import 'package:share_plus/share_plus.dart';

import 'error_reporter.dart';
import 'models/proxy.dart';
import 'proxy_parser.dart';
import 'proxy_tester.dart';
import 'singbox_engine.dart';
import 'storage.dart';

// ---------------------------------------------------------------------------
// Singleton engine instance — initialised once at startup.
// ---------------------------------------------------------------------------
final singBoxEngine = SingBoxTestEngine();

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  runApp(const ProxyCheckerApp());
}

// ---------------------------------------------------------------------------
// App shell — Material 3 dark theme, dynamic color seed
// ---------------------------------------------------------------------------
class ProxyCheckerApp extends StatelessWidget {
  const ProxyCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxy Checker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5B7FFF),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withAlpha(15)),
          ),
          color: const Color(0xFF161B22),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF161B22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF5B7FFF), width: 2),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab structure — Import / Results / Best
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  final _urlController = TextEditingController(
    text: 'https://raw.githubusercontent.com/AzadNetCH/Clash/main/AzadNet.txt',
  );

  List<Proxy> _proxies = [];
  List<Proxy> _results = [];
  bool _testing = false;
  bool _fetching = false;
  bool _speedTesting = false;
  int _testedCount = 0;

  // Engine status
  bool _engineReady = false;
  bool _engineInitialising = false;

  @override
  void initState() {
    super.initState();
    _warmUpAndRestore();
    _initEngine();
    _requestVpnPermissionIfNeeded();
  }

  /// Ask Android for VPN permission at launch so the native dialog appears
  /// immediately — not later in the middle of the first test run.
  Future<void> _requestVpnPermissionIfNeeded() async {
    // Small delay lets the first frame render before the system dialog shows.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      final granted = await singBoxEngine.isVpnPermissionGranted();
      if (!mounted) return;
      if (!granted) {
        final started = await singBoxEngine.startVpn();
        if (!mounted) return;
        if (!started) {
          _showSnack('Grant VPN permission to test proxies.');
        }
      }
    } catch (_) {
      // Engine not ready yet — the Test button flow will retry.
    }
  }

  /// Initialise storage asynchronously (never blocks/fails the first frame),
  /// then restore whatever persisted state is available.
  Future<void> _warmUpAndRestore() async {
    await ProxyStore.warmUp();
    if (!mounted) return;
    setState(() {
      _proxies = ProxyStore.loadProxies();
      _results = ProxyStore.loadResults();
    });
  }

  Future<void> _initEngine() async {
    setState(() => _engineInitialising = true);
    try {
      // Plugin init now answers immediately (service binding is async), so
      // a short timeout is enough. No 30s hang possible anymore.
      await singBoxEngine.init().timeout(const Duration(seconds: 10));
      if (mounted) setState(() => _engineReady = true);
    } catch (e, stack) {
      if (mounted) {
        final hint = e is TimeoutException
            ? 'VPN service did not respond. Tap Test to retry.'
            : '$e';
        _showError('Engine init', e, stack, fallback: 'Engine init failed: $hint');
      }
    } finally {
      if (mounted) setState(() => _engineInitialising = false);
    }
  }

  // ---- data loading helpers ------------------------------------------------

  void _loadFromText(String text, String sourceLabel) {
    final uris = extractProxyUris(text);
    final proxies = uris.map(parseProxyUri).whereType<Proxy>().toList();
    ProxyStore.saveProxies(proxies);
    setState(() {
      _proxies = proxies;
      _results = [];
    });
    ProxyStore.clearResults();
    _showSnack('Loaded ${proxies.length} proxies from $sourceLabel');
  }

  Future<void> _fetchFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _fetching = true);
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        _loadFromText(response.body, 'URL');
      } else {
        _showSnack('Fetch failed: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      _showSnack('Fetch timed out. Check your connection.');
    } catch (e, stack) {
      _showError('Fetch subscription', e, stack, fallback: 'Fetch failed: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text == null || text.trim().isEmpty) {
        _showSnack('Clipboard is empty');
        return;
      }
      _loadFromText(text, 'clipboard');
    } catch (e) {
      _showSnack('Failed to read clipboard: $e');
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'json'],
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final content = await File(path).readAsString();
      _loadFromText(content, 'file');
    } catch (e) {
      _showSnack('Failed to read file: $e');
    }
  }

  // ---- testing -------------------------------------------------------------

  Future<void> _startTesting() async {
    if (_proxies.isEmpty) return;
    setState(() {
      _testing = true;
      _testedCount = 0;
      _results = [];
      _currentTab = 1;
    });

    try {
      if (!_engineReady) {
        _showSnack('Initialising engine...');
        await singBoxEngine.init();
        if (mounted) setState(() => _engineReady = true);
      }
      // Permission gate: fire the native dialog before touching the service.
      // Show the hint ONLY when permission is not yet granted — never after
      // the user already approved (phantom dialog complaint).
      final granted = await singBoxEngine.isVpnPermissionGranted();
      if (!granted) {
        _showSnack('Tap Allow when the VPN permission dialog appears...');
        final started = await singBoxEngine.startVpn();
        if (!started) {
          _showSnack('VPN permission required. Grant it, then tap Test again.');
          return;
        }
      }
      final tagResults = await singBoxEngine.testGroup(_proxies);
      final applied = ProxyTester.applyGroupResults(
        _proxies,
        tagResults,
        (p) => singBoxEngine.tagFor(p as Proxy),
      );
      if (mounted) {
        setState(() {
          _results = applied;
          _testedCount = applied.length;
        });
        ProxyStore.saveResults(applied);
      }
    } catch (e, stack) {
      final msg = e.toString();
      if (msg.contains('VPN permission denied') || msg.contains('VPN_PERMISSION_DENIED')) {
        _showSnack('VPN permission required. Grant it, then tap Test again.');
      } else if (msg.contains('ALREADY_WAITING')) {
        _showSnack('VPN dialog is already open. Answer it or wait.');
      } else if (msg.contains('VPN_PERMISSION_TIMEOUT')) {
        _showSnack('No answer in 15s. Tap Test to try again.');
      } else if (msg.contains('NO_ACTIVITY') || msg.contains('PLUGIN_NOT_INIT')) {
        _showSnack('App lost focus. Return to main screen and tap Test.');
      } else if (msg.contains('INIT_FAILED') || msg.contains('service未响应') || msg.contains('VPN service failed')) {
        _showSnack('VPN service failed to start. Grant VPN permission, then tap Test.');
      } else {
        _showError('Test run', e, stack, fallback: 'Test failed: $e');
      }
    }

    if (mounted) setState(() => _testing = false);
  }

  Future<void> _speedTestAll() async {
    final working = _results.where((p) => p.working == true).toList();
    if (working.isEmpty) return;
    setState(() => _speedTesting = true);

    for (final proxy in working) {
      try {
        final data = await ProxyTester(singBoxEngine).speedTest(proxy);
        if (!mounted) return;
        setState(() {
          final idx = _results.indexWhere((p) => p.uri == proxy.uri);
          if (idx != -1) _results[idx] = _results[idx].copyWithSpeedData(data);
        });
      } catch (_) {
        // Per-proxy error — continue with remaining proxies.
      }
    }
    ProxyStore.saveResults(_results);

    if (mounted) setState(() => _speedTesting = false);
  }

  void _copyUri(String uri) {
    Clipboard.setData(ClipboardData(text: uri));
    _showSnack('Copied URI');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Shows an error snackbar with a "Report" action that opens the full
  /// diagnostic report (Copy + Share buttons). `fallback` is shown when
  /// the error is too long or unfriendly to display directly.
  void _showError(String where, Object error, StackTrace? stack,
      {required String fallback}) {
    final msg = error.toString();
    // Permission/known cases stay as plain snacks — no report needed.
    if (msg.contains('VPN permission denied') ||
        msg.contains('VPN_PERMISSION_DENIED')) {
      _showSnack(fallback);
      return;
    }
    ErrorReporter.showError(
      this,
      where: where,
      error: error,
      stack: stack,
      fallbackText: fallback,
      engineReady: _engineReady,
    );
  }

  Future<void> _shareResults() async {
    if (_results.isEmpty) return;
    try {
      final text = ResultExporter.toText(_results);
      await SharePlus.instance.share(ShareParams(text: text, subject: 'Proxy Checker results'));
    } catch (e) {
      _showSnack('Failed to share: $e');
    }
  }

  // ---- builders -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final best = ProxyTester.pickBest(_results);
    final workingCount = _results.where((p) => p.working == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Checker'),
        actions: [
          // Engine status indicator
          if (_engineInitialising)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                _engineReady ? Icons.check_circle_outline : Icons.error_outline,
                color: _engineReady ? Colors.greenAccent : Colors.orangeAccent,
                size: 22,
              ),
            ),
        ],
      ),
      body: _buildBody(best, workingCount),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: 'Import',
          ),
          NavigationDestination(
            icon: const Icon(Icons.speed_outlined),
            selectedIcon: const Icon(Icons.speed),
            label: 'Results',
          ),
          NavigationDestination(
            icon: const Icon(Icons.star_outline),
            selectedIcon: const Icon(Icons.star),
            label: 'Best',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Proxy? best, int workingCount) {
    return switch (_currentTab) {
      0 => _buildImportTab(),
      1 => _buildResultsTab(workingCount),
      2 => _buildBestTab(best),
      _ => const SizedBox.shrink(),
    };
  }

  // ---- TAB 1: Import -------------------------------------------------------
  Widget _buildImportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // URL bar
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'Subscription URL…',
            prefixIcon: const Icon(Icons.link, size: 20),
            suffixIcon: _fetching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _fetching ? null : _fetchFromUrl,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Fetch from URL'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('OR', style: TextStyle(color: Colors.white.withAlpha(120))),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _ImportCard(
                icon: Icons.content_paste,
                label: 'Paste',
                subtitle: 'from clipboard',
                onTap: _pasteFromClipboard,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ImportCard(
                icon: Icons.folder_open,
                label: 'File',
                subtitle: '.txt / .json',
                onTap: _importFromFile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Quick status
        if (_proxies.isNotEmpty) ...[
          _StatusBanner(
            icon: Icons.list_alt,
            text: '${_proxies.length} proxies ready',
            color: const Color(0xFF5B7FFF),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_testing || _engineInitialising) ? null : _startTesting,
              icon: _testing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_testing ? 'Testing… ($_testedCount/${_proxies.length})' : 'Start Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_testing) const LinearProgressIndicator(),
      ],
    );
  }

  // ---- TAB 2: Results ------------------------------------------------------
  Widget _buildResultsTab(int workingCount) {
    final displayResults = ProxyTester.sortedForDisplay(_results);

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 64, color: Colors.white.withAlpha(30)),
            const SizedBox(height: 16),
            Text(
              'No results yet',
              style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Import proxies and start a test',
              style: TextStyle(color: Colors.white.withAlpha(50), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.circle, size: 8, color: Colors.greenAccent.withAlpha(200)),
              const SizedBox(width: 6),
              Text(
                '$workingCount working',
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              Text(
                'of ${_results.length} tested',
                style: TextStyle(color: Colors.white.withAlpha(100)),
              ),
              const Spacer(),
              if (_speedTesting)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: workingCount == 0 ? null : _speedTestAll,
                      icon: const Icon(Icons.speed, size: 18),
                      label: const Text('Speed Test'),
                    ),
                    IconButton(
                      onPressed: _results.isEmpty ? null : _shareResults,
                      icon: const Icon(Icons.share, size: 20),
                      tooltip: 'Share results',
                    ),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 0),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayResults.length,
            itemBuilder: (context, i) {
              final p = displayResults[i];
              return _ProxyCard(proxy: p, onCopy: () => _copyUri(p.uri));
            },
          ),
        ),
      ],
    );
  }

  // ---- TAB 3: Best ---------------------------------------------------------
  Widget _buildBestTab(Proxy? best) {
    if (best == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 64, color: Colors.white.withAlpha(30)),
            const SizedBox(height: 16),
            Text(
              'No best proxy yet',
              style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Run a test to find the fastest proxy',
              style: TextStyle(color: Colors.white.withAlpha(50), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero card
        Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF5B7FFF).withAlpha(40),
                  const Color(0xFF5B7FFF).withAlpha(10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emoji_events, color: Colors.greenAccent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Best Proxy',
                            style: TextStyle(
                              color: Colors.white.withAlpha(160),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${best.protocol}  ${best.server}:${best.port}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Latency pill
                Row(
                  children: [
                    _LatencyPill(ms: best.latencyMs),
                    const SizedBox(width: 12),
                    if (best.speedData != null) ...[
                      _InfoChip(label: 'Jitter', value: '${best.speedData!.jitterMs.toStringAsFixed(0)} ms'),
                      const SizedBox(width: 8),
                      _InfoChip(label: 'Success', value: '${best.speedData!.successRate.toStringAsFixed(0)}%'),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                // Copy button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _copyUri(best.uri),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy URI'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // URI preview
        Text(
          'URI',
          style: TextStyle(
            color: Colors.white.withAlpha(120),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: SelectableText(
            best.uri,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFF8B949E),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---- Reusable widgets ------------------------------------------------------

class _ImportCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ImportCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: const Color(0xFF5B7FFF)),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatusBanner({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ProxyCard extends StatelessWidget {
  final Proxy proxy;
  final VoidCallback onCopy;

  const _ProxyCard({required this.proxy, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final sd = proxy.speedData;
    final subtitleParts = <String>[];
    if (proxy.latencyMs != null) {
      subtitleParts.add('${proxy.latencyMs!.toStringAsFixed(0)} ms');
    } else if (proxy.testType != null) {
      subtitleParts.add(proxy.testType!);
    }
    if (sd != null) {
      subtitleParts.add(
        'avg ${sd.avgMs.toStringAsFixed(0)}ms · jitter ${sd.jitterMs.toStringAsFixed(0)}ms · ${sd.successRate.toStringAsFixed(0)}% ok',
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: _LatencyIndicator(proxy: proxy),
        title: Text(
          '${proxy.protocol}  ${proxy.server}:${proxy.port}',
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: subtitleParts.isNotEmpty
            ? Text(subtitleParts.join(' · '), style: const TextStyle(fontSize: 12))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy URI',
          onPressed: onCopy,
        ),
      ),
    );
  }
}

class _LatencyIndicator extends StatelessWidget {
  final Proxy proxy;
  const _LatencyIndicator({required this.proxy});

  Color get _color {
    if (proxy.working != true) return Colors.redAccent;
    final ms = proxy.latencyMs ?? 999;
    if (ms < 200) return Colors.greenAccent;
    if (ms < 500) return Colors.orangeAccent;
    return Colors.amber;
  }

  IconData get _icon {
    if (proxy.working != true) return Icons.close;
    return Icons.circle;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _color.withAlpha(20),
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_icon, color: _color, size: 16),
          if (proxy.latencyMs != null)
            Text(
              '${proxy.latencyMs!.toStringAsFixed(0)}',
              style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _LatencyPill extends StatelessWidget {
  final double? ms;
  const _LatencyPill({required this.ms});

  @override
  Widget build(BuildContext context) {
    final latency = ms;
    if (latency == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 6),
          Text(
            '${latency.toStringAsFixed(0)} ms',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11)),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
