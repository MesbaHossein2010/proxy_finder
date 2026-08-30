import 'package:flutter_test/flutter_test.dart';

import 'package:proxy_checker_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders title and Import tab', (tester) async {
    await tester.pumpWidget(const ProxyCheckerApp());
    // Advance fake time past the 30s engine-init timeout so the pending
    // timer fires and no "pending timers" failure occurs at teardown.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 100));

    // App bar title
    expect(find.text('Proxy Checker'), findsWidgets);

    // Import tab elements
    expect(find.text('Fetch from URL'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);

    // Navigation bar
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
  });

  testWidgets('Results tab shows empty state', (tester) async {
    await tester.pumpWidget(const ProxyCheckerApp());
    await tester.pump(const Duration(seconds: 31));

    // Switch to Results tab
    await tester.tap(find.text('Results'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No results yet'), findsOneWidget);
  });

  testWidgets('Best tab shows empty state', (tester) async {
    await tester.pumpWidget(const ProxyCheckerApp());
    await tester.pump(const Duration(seconds: 31));

    await tester.tap(find.text('Best'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No best proxy yet'), findsOneWidget);
  });
}