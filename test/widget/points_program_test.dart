import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/logs/scan_log_tile.dart';
import 'package:qwallet_scan/scan/action_message.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/api/models/points_program.dart';
import 'package:qwallet_scan/scan/points_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard base({
  required String type,
  int pointsBalance = 0,
  String? membershipNumber,
  String? membershipCategory,
  DateTime? membershipExpiry,
  PointsProgramView? pointsProgram,
}) => LoyaltyCard(
  cardId: 'ABC1234567',
  businessId: 'biz-1',
  userName: 'Ali',
  userEmail: null,
  userPhone: null,
  templateType: type,
  stampCount: 0,
  rewardsAvailable: 0,
  stampsRequired: 0,
  rewardDescription: '',
  businessName: 'Wake',
  pointsBalance: pointsBalance,
  pointsExpiry: null,
  membershipNumber: membershipNumber,
  membershipCategory: membershipCategory,
  membershipExpiry: membershipExpiry,
  pointsProgram: pointsProgram,
);

PointsProgramView view({
  String method = 'amount',
  String mode = 'convert',
  List<Map<String, dynamic>> ready = const [],
}) => PointsProgramView.fromJson({
  'earn': method == 'amount'
      ? {'method': 'amount', 'rate': 1}
      : {
          'method': 'items',
          'items': [
            {'id': 'i1', 'name': 'Premium wash', 'points': 20},
          ],
        },
  'mode': mode,
  'rewards': [
    {
      'id': 'r1',
      'name': 'Free coffee',
      'points': 100,
      'affordable': mode == 'choose',
    },
  ],
  'readyRewards': ready,
  'nextReward': {'id': 'r1', 'name': 'Free coffee', 'pointsToGo': 20},
})!;

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester, LoyaltyCard c, Widget child) async {
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
                builder: (_, _) => Scaffold(body: child),
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
    // Same reason as the reward tests: these widgets only render inside
    // ScanFound, and their buttons are inert without a loaded card.
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  testWidgets('amount: preview, then Add purchase posts the amount', (
    tester,
  ) async {
    final c = base(type: 'points', pointsBalance: 80, pointsProgram: view());
    await pump(tester, c, PointsActions(card: c));
    api.pointsResult = PointsResult(
      pointsBalance: 167,
      pointsExpiry: null,
      pointsEarned: 87,
      rewardsIssued: const ['Free coffee'],
      pointsProgram: view(
        ready: [
          {'readyId': 'rd1', 'rewardId': 'r1', 'name': 'Free coffee'},
        ],
      ),
    );
    expect(find.text('20 points to Free coffee'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('points-bill')), '87.50');
    await tester.pump();
    expect(find.text('= 87 points · Free coffee ready'), findsOneWidget);
    await tester.tap(find.text('Add purchase'));
    await tester.pumpAndSettle();
    expect(api.actions, contains('earnPoints:amount:87.5'));
  });

  testWidgets('amount: Add purchase is disabled until the amount is valid', (
    tester,
  ) async {
    final c = base(type: 'points', pointsProgram: view());
    await pump(tester, c, PointsActions(card: c));
    await tester.enterText(find.byKey(const Key('points-bill')), '');
    await tester.pump();
    expect(find.text('Enter an amount'), findsOneWidget);
    await tester.tap(find.text('Add purchase'));
    await tester.pumpAndSettle();
    expect(api.actions.where((a) => a.startsWith('earnPoints')), isEmpty);
  });

  testWidgets('items: tapping an item earns its points x quantity', (
    tester,
  ) async {
    final c = base(
      type: 'points',
      pointsProgram: view(method: 'items'),
    );
    await pump(tester, c, PointsActions(card: c));
    api.pointsResult = PointsResult(
      pointsBalance: 40,
      pointsExpiry: null,
      pointsEarned: 40,
      pointsProgram: view(method: 'items'),
    );
    await tester.tap(find.byKey(const Key('points-qty-plus')));
    await tester.pump();
    await tester.tap(find.text('Premium wash +40'));
    await tester.pumpAndSettle();
    expect(api.actions, contains('earnPoints:item:i1:2'));
  });

  testWidgets('convert: one Redeem button per ready reward, sent by readyId', (
    tester,
  ) async {
    final c = base(
      type: 'points',
      pointsBalance: 30,
      pointsProgram: view(
        ready: [
          {'readyId': 'rd1', 'rewardId': 'r1', 'name': 'Free coffee'},
        ],
      ),
    );
    await pump(tester, c, PointsActions(card: c));
    api.pointsResult = PointsResult(
      pointsBalance: 30,
      pointsExpiry: null,
      rewardName: 'Free coffee',
      pointsProgram: view(),
    );
    await tester.ensureVisible(find.text('Redeem Free coffee'));
    await tester.tap(find.text('Redeem Free coffee'));
    await tester.pumpAndSettle();
    expect(api.actions, contains('redeemPointsReward:rd1'));
  });

  testWidgets('choose: affordable rewards are listed with their price', (
    tester,
  ) async {
    final c = base(
      type: 'points',
      pointsBalance: 120,
      pointsProgram: view(mode: 'choose'),
    );
    await pump(tester, c, PointsActions(card: c));
    expect(find.text('Redeem Free coffee (−100)'), findsOneWidget);
  });

  testWidgets('manual card keeps the old Add/Deduct screen', (tester) async {
    final c = base(type: 'points', pointsBalance: 5);
    await pump(tester, c, PointsActions(card: c));
    expect(find.text('Add Points'), findsOneWidget);
    expect(find.text('Add purchase'), findsNothing);
  });

  testWidgets('amount preview says when the purchase issues the next reward', (
    tester,
  ) async {
    final c = base(type: 'points', pointsBalance: 80, pointsProgram: view());
    await pump(tester, c, PointsActions(card: c));
    await tester.enterText(find.byKey(const Key('points-bill')), '10');
    await tester.pump();
    expect(find.text('= 10 points'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('points-bill')), '25');
    await tester.pump();
    expect(find.text('= 25 points · Free coffee ready'), findsOneWidget);
  });

  testWidgets('choose: the confirmation names the reward the server redeemed', (
    tester,
  ) async {
    final c = base(
      type: 'points',
      pointsBalance: 120,
      pointsProgram: view(mode: 'choose'),
    );
    await pump(tester, c, PointsActions(card: c));
    api.pointsResult = PointsResult(
      pointsBalance: 20,
      pointsExpiry: null,
      rewardName: 'Free espresso',
      pointsProgram: view(mode: 'choose'),
    );
    await tester.tap(find.text('Redeem Free coffee (−100)'));
    await tester.pumpAndSettle();
    expect(
      tester.container().read(actionMessageProvider),
      'Redeemed Free espresso. Balance 20.',
    );
  });

  testWidgets('a refused redeem reloads the card so a stale button goes away', (
    tester,
  ) async {
    final c = base(
      type: 'points',
      pointsBalance: 30,
      pointsProgram: view(
        ready: [
          {'readyId': 'rd1', 'rewardId': 'r1', 'name': 'Free coffee'},
        ],
      ),
    );
    await pump(tester, c, PointsActions(card: c));
    final lookupsBefore = api.fetchedCardIds.length;
    api.card = base(type: 'points', pointsBalance: 30, pointsProgram: view());
    api.actionError = ApiException(
      ApiErrorKind.badRequest,
      'No reward ready to redeem',
    );
    await tester.ensureVisible(find.text('Redeem Free coffee'));
    await tester.tap(find.text('Redeem Free coffee'));
    await tester.pumpAndSettle();
    expect(api.fetchedCardIds.length, lookupsBefore + 1);
    expect(find.text('Redeem Free coffee'), findsNothing);
    expect(find.text('No reward ready to redeem'), findsOneWidget);
  });

  testWidgets('an adjust that issues a reward says so', (tester) async {
    final c = base(type: 'points', pointsBalance: 80, pointsProgram: view());
    await pump(tester, c, PointsActions(card: c));
    api.pointsResult = PointsResult(
      pointsBalance: 30,
      pointsExpiry: null,
      readyRewards: const [
        ReadyReward(readyId: 'rd1', rewardId: 'r1', name: 'Free coffee'),
      ],
      pointsProgram: view(
        ready: [
          {'readyId': 'rd1', 'rewardId': 'r1', 'name': 'Free coffee'},
        ],
      ),
    );
    await tester.enterText(find.byKey(const Key('points-amount')), '50');
    await tester.ensureVisible(find.text('Add Points'));
    await tester.tap(find.text('Add Points'));
    await tester.pumpAndSettle();
    expect(
      tester.container().read(actionMessageProvider),
      'Added 50 points. Balance 30 · Free coffee ready.',
    );
  });

  testWidgets('activity log rows for points read as points, not stamps', (
    tester,
  ) async {
    Widget tile(Map<String, dynamic> json) => MaterialApp(
      home: Scaffold(body: ScanLogTile(entry: ScanLogEntry.fromJson(json))),
    );
    final base0 = {
      'id': 1,
      'cardId': 'PTS1',
      'staffName': 'Till',
      'customerName': 'Ada',
      'loggedAt': '2026-10-11T10:00:00.000Z',
    };
    await tester.pumpWidget(
      tile({
        ...base0,
        'type': 'points_earn',
        'stampsAdded': 87,
        'stampsBefore': 80,
        'stampsAfter': 67,
        'billAmount': '87.50',
        'itemName': null,
        'rewardName': 'Free coffee',
      }),
    );
    expect(
      find.text(
        'Purchase QAR 87.50 · +87 points · Free coffee ready · 80 → 67 pts · Till',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(
      tile({
        ...base0,
        'type': 'points_redeem',
        'stampsAdded': 0,
        'stampsBefore': 130,
        'stampsAfter': 130,
        'rewardName': 'Free coffee',
      }),
    );
    expect(
      find.text('Redeemed Free coffee · 130 → 130 pts · Till'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      tile({
        ...base0,
        'type': 'points_adjust',
        'stampsAdded': -10,
        'stampsBefore': 40,
        'stampsAfter': 30,
      }),
    );
    expect(
      find.text('Adjusted −10 points · 40 → 30 pts · Till'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      tile({
        ...base0,
        'type': 'points_earn',
        'stampsAdded': 60,
        'stampsBefore': 0,
        'stampsAfter': 60,
        'itemName': 'Premium wash ×3',
      }),
    );
    expect(
      find.text('Premium wash ×3 · +60 points · 0 → 60 pts · Till'),
      findsOneWidget,
    );
  });
}
