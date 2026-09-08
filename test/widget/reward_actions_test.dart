import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';
import 'package:qwallet_scan/scan/reward_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard card({int stampCount = 3, int rewardsAvailable = 0}) => LoyaltyCard(
  cardId: 'ABC1234567',
  businessId: 'biz-1',
  userName: 'Ali',
  userEmail: 'a@b.qa',
  userPhone: null,
  templateType: 'reward',
  stampCount: stampCount,
  rewardsAvailable: rewardsAvailable,
  stampsRequired: 10,
  rewardDescription: 'A free flat white',
  businessName: 'Wake',
  pointsBalance: 0,
  pointsExpiry: null,
  membershipNumber: null,
  membershipCategory: null,
  membershipExpiry: null,
);

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester, LoyaltyCard c) async {
    api = FakeApiClient();
    api.card = c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        // MaterialApp.router, not MaterialApp: a finished action sends the
        // till back to /home, so these buttons need somewhere to send it.
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(body: RewardActions(card: c)),
              ),
              GoRoute(
                path: '/home',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Dashboard'))),
              ),
            ],
          ),
        ),
      ),
    );
    // This widget only ever renders inside ScanFound, so the notifier is put
    // there too. Without it the buttons are correctly inert — _act refuses to
    // run against a notifier holding no card — and every action test would be
    // asserting on a state the app never reaches.
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the stamp count and the reward on offer', (tester) async {
    await pump(tester, card(stampCount: 7));

    expect(find.text('7 / 10 stamps'), findsOneWidget);
    expect(find.text('A free flat white'), findsOneWidget);
  });

  testWidgets('all three actions are tappable on a part-filled card', (
    tester,
  ) async {
    // Neither Add to Rewards nor Redeem is gated on a local rule: the
    // add-reward threshold on a multi-milestone card is a cumulative sum this
    // app is not given, and redeem is legal straight off a completed card with
    // no banked rewards. The server decides; see the spec.
    await pump(tester, card(stampCount: 3, rewardsAvailable: 0));

    // FilledButton, not ButtonStyleButton: find.byType compares runtimeType
    // exactly, so the abstract base matches nothing. FilledButton.tonal is a
    // factory on the same class, so this covers all three buttons.
    for (final label in ['Add Stamps', 'Add to Rewards', 'Redeem']) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, label),
      );
      expect(button.onPressed, isNotNull, reason: '$label must stay tappable');
    }
  });

  testWidgets('Redeem asks before it takes anything away', (tester) async {
    await pump(tester, card(rewardsAvailable: 1));

    await tester.tap(find.widgetWithText(FilledButton, 'Redeem'));
    await tester.pumpAndSettle();

    expect(find.text('Redeem a reward?'), findsOneWidget);
    expect(api.actions, isEmpty, reason: 'nothing until it is confirmed');
  });

  testWidgets('confirming the dialog performs the redemption', (tester) async {
    await pump(tester, card(rewardsAvailable: 1));
    api.actionResult = const CardActionResult(
      stampCount: 0,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Redeem'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Redeem'));
    await tester.pumpAndSettle();

    expect(api.actions, ['redeem']);
  });

  testWidgets('the increment can be raised and is what gets sent', (
    tester,
  ) async {
    await pump(tester, card());
    api.actionResult = const CardActionResult(
      stampCount: 6,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(api.actions, ['addStamps:3']);
  });

  testWidgets('the increment never goes below one', (tester) async {
    await pump(tester, card());

    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a finished stamp says so and hands back the dashboard', (
    tester,
  ) async {
    await pump(tester, card(stampCount: 3));
    api.actionResult = const CardActionResult(
      stampCount: 4,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('Stamped. 4 of 10.'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('a refusal keeps the card on screen, with the reason', (
    tester,
  ) async {
    await pump(tester, card(stampCount: 3));
    api.actionError = ApiException.fromResponse(
      400,
      '{"error":"This card has expired"}',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('This card has expired'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing, reason: 'nothing happened');
  });

  testWidgets('stamping the same card twice in a minute asks first', (
    tester,
  ) async {
    await pump(tester, card(stampCount: 3));
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record('ABC1234567', CardAction.stamps);

    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('Already done'), findsOneWidget);
    expect(find.textContaining('added stamps to this card'), findsOneWidget);
    expect(api.actions, isEmpty, reason: 'nothing until it is confirmed');
  });

  testWidgets('backing out of the repeat warning does nothing at all', (
    tester,
  ) async {
    await pump(tester, card(stampCount: 3));
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record('ABC1234567', CardAction.stamps);

    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.actions, isEmpty);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('a different card is not caught by the warning', (tester) async {
    await pump(tester, card(stampCount: 3));
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record('SOMEONEELSE', CardAction.stamps);
    api.actionResult = const CardActionResult(
      stampCount: 4,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(api.actions, ['addStamps:1']);
  });
}
