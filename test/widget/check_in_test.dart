import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/check_in_summary.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/logs/scan_log_tile.dart';
import 'package:qwallet_scan/scan/action_message.dart';
import 'package:qwallet_scan/scan/card_result_view.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard base({required String type, CheckInSummary? checkIn}) =>
    LoyaltyCard(
      cardId: 'ABC1234567',
      businessId: 'biz-1',
      userName: 'Ali',
      userEmail: null,
      userPhone: null,
      templateType: type,
      stampCount: 0,
      rewardsAvailable: 0,
      stampsRequired: type == 'reward' ? 10 : 0,
      rewardDescription: '',
      businessName: 'Habanos Lounge',
      pointsBalance: 0,
      pointsExpiry: null,
      membershipNumber: type == 'membership' ? 'HL-0001' : null,
      membershipCategory: null,
      membershipExpiry: null,
      checkIn: checkIn,
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
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(body: CardResultView(card: c)),
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

  final summary = CheckInSummary(
    visits: 2,
    lastCheckInAt: DateTime.utc(2026, 10, 8, 16, 35),
  );

  testWidgets('a membership card shows Check in above Renew', (tester) async {
    await pump(tester, base(type: 'membership', checkIn: summary));
    expect(find.text('Check in'), findsOneWidget);
    expect(find.textContaining('Visit 2'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Check in')).dy,
      lessThan(tester.getTopLeft(find.text('Renew')).dy),
    );
  });

  testWidgets('a first visit says so', (tester) async {
    await pump(
      tester,
      base(
        type: 'membership',
        checkIn: const CheckInSummary(visits: 0, lastCheckInAt: null),
      ),
    );
    expect(find.text('First visit'), findsOneWidget);
  });

  testWidgets('a reward card has no Check in', (tester) async {
    await pump(tester, base(type: 'reward'));
    expect(find.text('Check in'), findsNothing);
  });

  testWidgets('tapping checks in and confirms the new visit count', (
    tester,
  ) async {
    await pump(tester, base(type: 'membership', checkIn: summary));
    api.checkInResult = CheckInSummary(
      visits: 3,
      lastCheckInAt: DateTime.utc(2026, 10, 8, 17),
    );
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(api.actions, ['checkIn']);
    // Back at the dashboard, which raises the confirmation (action_flow.dart).
    expect(find.text('Dashboard'), findsOneWidget);
    expect(
      tester.container().read(actionMessageProvider),
      'Checked in. Visit 3.',
    );
  });

  testWidgets('a second check-in within a minute asks first', (tester) async {
    final c = base(type: 'membership', checkIn: summary);
    await pump(tester, c);
    tester
        .container()
        .read(recentActionsProvider.notifier)
        .record(c.cardId, CardAction.checkIn);
    api.checkInResult = CheckInSummary(
      visits: 3,
      lastCheckInAt: DateTime.utc(2026, 10, 8, 17),
    );

    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();

    expect(find.text('Already done'), findsOneWidget);
    expect(find.textContaining('You checked in this card'), findsOneWidget);
    expect(find.text('Check in anyway'), findsOneWidget);
    expect(api.actions, isEmpty);

    await tester.tap(find.text('Check in anyway'));
    await tester.pumpAndSettle();
    expect(api.actions, ['checkIn']);
  });

  test('the log parses check_in', () {
    final e = ScanLogEntry.fromJson({
      'id': 1,
      'type': 'check_in',
      'cardId': 'X',
      'loggedAt': '2026-10-08T16:35:00Z',
    });
    expect(e.type, ScanLogType.checkIn);
  });

  test('the card parses checkIn, and its absence', () {
    Map<String, dynamic> json(Object? checkIn) => {
      'cardId': 'X',
      'businessId': 'b',
      'templateType': 'membership',
      'checkIn': checkIn,
    };
    final c = LoyaltyCard.fromJson(
      json({'visits': 4, 'lastCheckInAt': '2026-10-08T16:35:00.000Z'}),
    );
    expect(c.checkIn?.visits, 4);
    expect(c.checkIn?.lastCheckInAt, DateTime.utc(2026, 10, 8, 16, 35));
    expect(LoyaltyCard.fromJson(json(null)).checkIn, isNull);
  });

  testWidgets(
    'a check-in log row says Checked in, not +0 stamps (Review Focus 3)',
    (tester) async {
      final e = ScanLogEntry.fromJson({
        'id': 1,
        'type': 'check_in',
        'cardId': 'X',
        'customerName': null,
        'loggedAt': '2026-10-08T16:35:00Z',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScanLogTile(entry: e)),
        ),
      );
      expect(find.textContaining('Checked in'), findsOneWidget);
      expect(find.textContaining('+0'), findsNothing);
      expect(find.text('Customer'), findsOneWidget);
    },
  );

  testWidgets('a refused check-in shows its reason once, above Renew', (
    tester,
  ) async {
    await pump(tester, base(type: 'membership', checkIn: summary));
    api.actionError = ApiException.fromResponse(
      403,
      '{"error":"Access denied"}',
    );

    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();

    expect(
      find.text("You don't have access to this business."),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.text("You don't have access to this business."))
          .dy,
      lessThan(tester.getTopLeft(find.text('Renew')).dy),
    );
    expect(find.text('Dashboard'), findsNothing);
  });
}
