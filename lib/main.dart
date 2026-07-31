import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'models/proxy.dart';
import 'proxy_parser.dart';
import 'proxy_tester.dart';
import 'singbox_engine.dart';

final singBoxEngine = SingBoxTestEngine();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  runApp(const ProxyCheckerApp());
}

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
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController(text: "https://raw.githubusercontent.com/AzadNetCH/Clash/main/AzadNet.txt");

  List<Proxy> _proxies = [];
  List<Proxy> _results = [];
  bool _testing = false;
  bool _fetching = false;
  bool _speedTesting = false;
  int _testedCount = 0;
  @override
  void initState() {
    super.initState();
    singBoxEngine.init();
  }

  void _loadFromText(String text, String sourceLabel) {
    final uris = extractProxyUris(text);
    final proxies = uris.map(parseProxyUri).whereType<Proxy>().toList();
    setState(() {
      _proxies = proxies;
      _results = [];
    });
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
    } catch (e) {
      _showSnack('Fetch failed: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  // Matches desktop's _paste(): reads system clipboard directly, no
  // visible text box for pasted content.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      _showSnack('Clipboard is empty');
      return;
    }
    _loadFromText(text, 'clipboard');
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'json']);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final content = await File(path).readAsString();
    _loadFromText(content, 'file');
  }

  Future<void> _startTesting() async {
    if (_proxies.isEmpty) return;
    setState(() {
      _testing = true;
      _testedCount = 0;
      _results = [];
    });

    try {
      // Re-run init() here (awaited) so we're certain the Android Activity
      // is attached — the earlier initState() call wasn't awaited and may
      // have silently failed if the Activity wasn't ready at app cold start.
      await singBoxEngine.init();
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
      }
    } catch (e) {
      _showSnack('Test failed: $e');
    }

    if (mounted) setState(() => _testing = false);
  }

  Future<void> _speedTestAll() async {
    final working = _results.where((p) => p.working == true).toList();
    if (working.isEmpty) return;
    setState(() => _speedTesting = true);

    for (final proxy in working) {
      final data = null; // speed test needs its own pass over singBoxEngine — next iteration
      if (!mounted) return;
      setState(() {
        final idx = _results.indexWhere((p) => p.uri == proxy.uri);
        if (idx != -1) _results[idx] = _results[idx].copyWithSpeedData(data);
      });
    }

    if (mounted) setState(() => _speedTesting = false);
  }


  void _copyUri(String uri) {
    Clipboard.setData(ClipboardData(text: uri));
    _showSnack('Copied URI');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final best = ProxyTester.pickBest(_results);
    final workingCount = _results.where((p) => p.working == true).length;
    final displayResults = ProxyTester.sortedForDisplay(_results);

    return Scaffold(
      appBar: AppBar(title: const Text('Proxy Checker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- URL bar (matches desktop's single URL field) ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter subscription URL...',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _fetching ? null : _fetchFromUrl,
                  child: _fetching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Fetch'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // --- Paste from clipboard / file import (no visible paste box) ---
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste from Clipboard'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importFromFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import File'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('${_proxies.length} proxies loaded', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),

            // --- Test controls ---
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_proxies.isEmpty || _testing) ? null : _startTesting,
                    child: Text(_testing ? 'Testing ($_testedCount/${_proxies.length})...' : 'Start Test'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (workingCount == 0 || _speedTesting) ? null : _speedTestAll,
                    child: Text(_speedTesting ? 'Speed Testing...' : 'Speed Test All'),
                  ),
                ),
              ],
            ),
            if (_testing || _speedTesting)
              const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            if (_results.isNotEmpty) Text('$workingCount working / ${_results.length} tested — sorted by ping'),

            // --- Results list ---
            Expanded(
              child: ListView.builder(
                itemCount: displayResults.length,
                itemBuilder: (context, i) {
                  final p = displayResults[i];
                  final ok = p.working == true;
                  final sd = p.speedData;
                  final subtitleParts = <String>[];
                  if (p.latencyMs != null) {
                    subtitleParts.add('${p.latencyMs!.toStringAsFixed(0)} ms');
                  } else if (p.testType != null) {
                    subtitleParts.add(p.testType!);
                  }
                  if (sd != null) {
                    subtitleParts.add(
                        'speed: avg ${sd.avgMs.toStringAsFixed(0)}ms, jitter ${sd.jitterMs.toStringAsFixed(0)}ms, ${sd.successRate.toStringAsFixed(0)}% ok');
                  }
                  return ListTile(
                    leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.redAccent),
                    title: Text('${p.protocol} — ${p.server}:${p.port}'),
                    subtitle: Text(subtitleParts.join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      tooltip: 'Copy URI',
                      onPressed: () => _copyUri(p.uri),
                    ),
                  );
                },
              ),
            ),

            // --- Best proxy (copy only, no connect) ---
            if (best != null)
              Card(
                color: const Color(0xFF1A1A2E),
                child: ListTile(
                  title: Text('Best: ${best.protocol} — ${best.server}'),
                  subtitle: Text('${best.latencyMs!.toStringAsFixed(0)} ms'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy URI',
                    onPressed: () => _copyUri(best.uri),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
