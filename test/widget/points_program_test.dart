import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
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
    expect(find.text('= 87 points'), findsOneWidget);
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
}
