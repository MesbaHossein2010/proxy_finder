import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models/proxy.dart';
import 'proxy_parser.dart';
import 'proxy_engine.dart';
import 'proxy_tester.dart';
import 'mock_engine.dart';

// Swap MockEngine() for your real plugin-backed engine once one is chosen
// and vetted. Nothing else in this file needs to change to do that.
final ProxyEngine engine = MockEngine();

void main() {
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
  final _pasteController = TextEditingController();
  List<Proxy> _proxies = [];
  List<Proxy> _results = [];
  bool _testing = false;
  int _testedCount = 0;
  bool _connected = false;
  Proxy? _connectedProxy;

  late final ProxyTester _tester;

  @override
  void initState() {
    super.initState();
    _tester = ProxyTester(engine);
    engine.init();
    engine.connectionStatus.listen((status) {
      if (mounted) setState(() => _connected = status);
    });
  }

  void _importFromText() {
    final uris = extractProxyUris(_pasteController.text);
    final proxies = uris.map(parseProxyUri).whereType<Proxy>().toList();
    setState(() {
      _proxies = proxies;
      _results = [];
    });
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'json']);    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final content = await File(path).readAsString();
    final uris = extractProxyUris(content);
    final proxies = uris.map(parseProxyUri).whereType<Proxy>().toList();
    setState(() {
      _proxies = proxies;
      _results = [];
    });
  }

  Future<void> _startTesting() async {
    if (_proxies.isEmpty) return;
    setState(() {
      _testing = true;
      _testedCount = 0;
      _results = [];
    });

    await for (final result in _tester.testAll(_proxies, concurrency: 10)) {
      if (!mounted) return;
      setState(() {
        _results.add(result);
        _testedCount++;
      });
    }

    if (mounted) setState(() => _testing = false);
  }

  Future<void> _toggleConnection() async {
    if (_connected) {
      await engine.disconnect();
      setState(() => _connectedProxy = null);
      return;
    }
    final best = ProxyTester.pickBest(_results);
    if (best == null) return;
    await engine.connect(best);
    setState(() => _connectedProxy = best);
  }

  @override
  Widget build(BuildContext context) {
    final best = ProxyTester.pickBest(_results);
    final workingCount = _results.where((p) => p.working == true).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Proxy Checker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pasteController,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste subscription URL content or proxy URIs here',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(onPressed: _importFromText, child: const Text('Import Pasted Text')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: _importFromFile, child: const Text('Import File')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('${_proxies.length} proxies loaded', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_proxies.isEmpty || _testing) ? null : _startTesting,
              child: Text(_testing ? 'Testing ($_testedCount/${_proxies.length})...' : 'Start Test'),
            ),
            if (_testing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            if (_results.isNotEmpty) Text('$workingCount working / ${_results.length} tested'),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final p = _results[i];
                  final ok = p.working == true;
                  return ListTile(
                    leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.redAccent),
                    title: Text('${p.protocol} — ${p.server}:${p.port}'),
                    subtitle: Text(p.latencyMs != null ? '${p.latencyMs!.toStringAsFixed(0)} ms' : p.testType ?? ''),
                  );
                },
              ),
            ),
            if (best != null)
              Card(
                color: const Color(0xFF1A1A2E),
                child: ListTile(
                  title: Text('Best: ${best.protocol} — ${best.server}'),
                  subtitle: Text('${best.latencyMs!.toStringAsFixed(0)} ms'),
                  trailing: FilledButton(
                    onPressed: _toggleConnection,
                    child: Text(_connected ? 'Disconnect' : 'Connect'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
