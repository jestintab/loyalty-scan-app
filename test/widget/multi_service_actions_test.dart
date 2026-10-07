import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/action_message.dart';
import 'package:qwallet_scan/scan/card_result_view.dart';
import 'package:qwallet_scan/scan/multi_service_actions.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';
import '../support/multi_service_fixtures.dart';

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
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: SingleChildScrollView(
                    child: MultiServiceActions(card: c),
                  ),
                ),
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
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  testWidgets('shows both services and no actions until one is picked', (
    tester,
  ) async {
    await pump(tester, multiCard());

    expect(find.text('Mani/Pedi'), findsOneWidget);
    expect(find.text('Blowdry'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('1 reward waiting'), findsOneWidget);
    expect(find.text('4 more to reward'), findsOneWidget);
    expect(find.text('Pick the service the customer had.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('picking a service shows its own controls', (tester) async {
    await pump(tester, multiCard());

    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    expect(button('Add Blowdry Stamps'), findsOneWidget);
    expect(button('Add to Blowdry Rewards'), findsOneWidget);
    expect(button('Redeem Blowdry Reward'), findsOneWidget);
    expect(find.text('Pick the service the customer had.'), findsNothing);
  });

  testWidgets('the increment stops at the end of the cycle (Review Focus 2)', (
    tester,
  ) async {
    await pump(
      tester,
      multiCard(
        services: [
          service('s1', 'Mani/Pedi', 2, 5),
          service('s2', 'Blowdry', 4, 5),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }

    expect(find.text('1'), findsOneWidget);
    final plus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(plus.onPressed, isNull);
  });

  testWidgets('a stamp sends the service and names it in the confirmation', (
    tester,
  ) async {
    await pump(tester, multiCard());
    api.actionResult = CardActionResult(
      stampCount: 5,
      stampsRequired: 0,
      rewardsAvailable: 1,
      services: [
        service('s1', 'Mani/Pedi', 2, 5, rewards: 1),
        service('s2', 'Blowdry', 3, 5),
      ],
    );
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pumpAndSettle();

    expect(api.actions, ['addStamps:2@s2']);
    // Spec §4: the selection stays put after an action, so the other service
    // can be done in the same visit without scanning the card again.
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Blowdry stamped. 3 of 5.'), findsOneWidget);
    expect(button('Add Blowdry Stamps'), findsOneWidget);
    expect(tester.container().read(actionMessageProvider), isNull);
  });

  testWidgets('the repeat warning is per service (Review Focus 1)', (
    tester,
  ) async {
    await pump(tester, multiCard());
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record('MSC1234567:s1', CardAction.stamps);
    api.actionResult = CardActionResult(
      stampCount: 4,
      stampsRequired: 0,
      rewardsAvailable: 1,
      services: multiCard().services,
    );

    // The other service: no warning, the stamp goes straight through.
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();
    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pumpAndSettle();
    expect(find.text('Already done'), findsNothing);
    expect(api.actions, ['addStamps:1@s2']);
  });

  testWidgets('the same service within a minute still asks', (tester) async {
    await pump(tester, multiCard());
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record('MSC1234567:s1', CardAction.stamps);

    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pumpAndSettle();
    await tester.tap(button('Add Mani/Pedi Stamps'));
    await tester.pumpAndSettle();

    expect(find.text('Already done'), findsOneWidget);
    expect(api.actions, isEmpty);
  });

  testWidgets('redeem asks with the service name before taking anything', (
    tester,
  ) async {
    await pump(tester, multiCard());
    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pumpAndSettle();

    await tester.tap(button('Redeem Mani/Pedi Reward'));
    await tester.pumpAndSettle();

    expect(find.text('Redeem a Mani/Pedi reward?'), findsOneWidget);
    expect(api.actions, isEmpty);
  });

  testWidgets(
    'a refusal keeps the card, the reason and the picked service (Review Focus 5)',
    (tester) async {
      await pump(tester, multiCard());
      api.actionError = ApiException.fromResponse(
        409,
        '{"error":"Card was updated concurrently, please retry"}',
      );
      await tester.tap(find.byKey(const Key('service-s2')));
      await tester.pumpAndSettle();

      await tester.tap(button('Add Blowdry Stamps'));
      await tester.pumpAndSettle();

      expect(
        find.text('Card was updated concurrently, please retry'),
        findsOneWidget,
      );
      expect(button('Add Blowdry Stamps'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    },
  );

  testWidgets('the card screen routes a multi-service card here', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(FakeApiClient()),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp(
          home: Scaffold(body: CardResultView(card: multiCard())),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MultiServiceActions), findsOneWidget);
    expect(
      find.text("This card type isn't supported in this app"),
      findsNothing,
    );
  });

  testWidgets('switching service clears the other service\'s refusal', (
    tester,
  ) async {
    await pump(tester, multiCard());
    api.actionError = ApiException.fromResponse(
      400,
      '{"error":"No reward available to redeem"}',
    );
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();
    await tester.tap(button('Redeem Blowdry Reward'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Redeem'));
    await tester.pumpAndSettle();
    expect(find.text('No reward available to redeem'), findsOneWidget);

    // Mani/Pedi does have a reward: Blowdry's refusal must not appear there.
    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pumpAndSettle();

    expect(find.text('No reward available to redeem'), findsNothing);
  });

  testWidgets('the services cannot be switched while an action is in flight', (
    tester,
  ) async {
    await pump(tester, multiCard());
    final gate = Completer<void>();
    api.gate = gate.future;
    api.actionResult = CardActionResult(
      stampCount: 4,
      stampsRequired: 0,
      rewardsAvailable: 1,
      services: [
        service('s1', 'Mani/Pedi', 2, 5, rewards: 1),
        service('s2', 'Blowdry', 2, 5),
      ],
    );
    await tester.tap(find.byKey(const Key('service-s2')));
    await tester.pumpAndSettle();

    await tester.tap(button('Add Blowdry Stamps'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('service-s1')));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    // Still on Blowdry, and the stamp that landed is confirmed.
    expect(button('Add Blowdry Stamps'), findsOneWidget);
    expect(find.text('Blowdry stamped. 2 of 5.'), findsOneWidget);
    expect(api.actions, ['addStamps:1@s2']);
  });
}
