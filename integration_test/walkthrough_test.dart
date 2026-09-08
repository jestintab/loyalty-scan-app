// A scripted walk through the app on a real device, against a real API.
//
// Not part of the test suite `flutter test` runs — this needs a device and a
// server. It exists so the app can be driven to each screen and photographed
// without GUI automation, which needs Accessibility permissions a CI box or a
// non-interactive shell does not have.
//
// Run with:
//   fvm flutter test integration_test/walkthrough_test.dart \
//     -d <simulator-id> --dart-define=API_BASE_URL=http://localhost:5599
//
// It pauses at each checkpoint so an outside `xcrun simctl io booted
// screenshot` can catch it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qwallet_scan/app.dart';

const _hold = Duration(seconds: 10);

Future<void> settle(WidgetTester tester) async {
  // pumpAndSettle would hang on the camera preview's continuous frames, so
  // time-box the settle instead.
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign in, scan a card, read the log', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QwalletScanApp()));
    await settle(tester);

    // A previous run's token is still in the keychain — which is the session
    // persistence working, but it starts this walk on the dashboard. Sign out
    // so the walk always begins where it means to.
    if (find.byKey(const Key('identifier')).evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.logout));
      await settle(tester);
    }

    // ---- 1. Login ----
    await tester.enterText(find.byKey(const Key('identifier')), 'sam@wake.qa');
    await tester.enterText(find.byKey(const Key('password')), 'counter123');
    await settle(tester);
    debugPrint('SHOT-READY: login');
    await tester.pump(_hold);

    await tester.tap(find.text('Sign in'));
    await settle(tester);
    debugPrint('SHOT-READY: home');
    await tester.pump(_hold);

    // ---- 2. The dashboard opens the scanner ----
    await tester.tap(find.text('Start scanning'));
    await settle(tester);
    debugPrint('SHOT-READY: scan');
    await tester.pump(_hold);

    // ---- 3. Scan screen: look the card up by id ----
    await tester.enterText(find.byType(TextField).last, 'WAKE001');
    await settle(tester);
    await tester.tap(find.text('Look up'));
    await settle(tester);
    debugPrint('SHOT-READY: card');
    await tester.pump(_hold);

    // ---- 4. The card, with its three reward actions ----
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    debugPrint('SHOT-READY: card-stamped');
    await tester.pump(_hold);

    // ---- 5. Stamping reports and hands the till back to the dashboard ----
    await tester.tap(find.text('Add Stamps'));
    await settle(tester);
    debugPrint('SHOT-READY: stamped-home');
    await tester.pump(_hold);

    // ---- 6. The scan log ----
    await tester.tap(find.text('Full scan log'));
    await settle(tester);
    debugPrint('SHOT-READY: log');
    await tester.pump(_hold);
  });
}
