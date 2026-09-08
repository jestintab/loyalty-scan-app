import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/membership_actions.dart';
import 'package:qwallet_scan/scan/points_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard base({
  required String type,
  int pointsBalance = 0,
  String? membershipNumber,
  String? membershipCategory,
  DateTime? membershipExpiry,
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
);

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

  group('PointsActions', () {
    testWidgets('shows the balance', (tester) async {
      final c = base(type: 'points', pointsBalance: 250);
      await pump(tester, c, PointsActions(card: c));

      expect(find.text('250 points'), findsOneWidget);
    });

    testWidgets('Add sends a positive amount', (tester) async {
      final c = base(type: 'points');
      await pump(tester, c, PointsActions(card: c));
      api.pointsResult = const PointsResult(
        pointsBalance: 50,
        pointsExpiry: null,
      );

      await tester.enterText(find.byKey(const Key('points-amount')), '50');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Points'));
      await tester.pumpAndSettle();

      expect(api.actions, ['adjustPoints:50']);
    });

    testWidgets('Deduct sends the negative of the same amount', (tester) async {
      final c = base(type: 'points', pointsBalance: 100);
      await pump(tester, c, PointsActions(card: c));
      api.pointsResult = const PointsResult(
        pointsBalance: 70,
        pointsExpiry: null,
      );

      await tester.enterText(find.byKey(const Key('points-amount')), '30');
      await tester.tap(find.widgetWithText(FilledButton, 'Deduct Points'));
      await tester.pumpAndSettle();

      expect(api.actions, ['adjustPoints:-30']);
    });

    testWidgets('a non-numeric amount is refused before any call', (
      tester,
    ) async {
      final c = base(type: 'points');
      await pump(tester, c, PointsActions(card: c));

      await tester.enterText(find.byKey(const Key('points-amount')), 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Points'));
      await tester.pumpAndSettle();

      expect(api.actions, isEmpty);
      expect(find.text('Enter a number of points'), findsOneWidget);
    });
  });

  group('MembershipActions', () {
    testWidgets('shows the number, category and expiry', (tester) async {
      final c = base(
        type: 'membership',
        membershipNumber: 'MBR-0007',
        membershipCategory: 'Gold',
        membershipExpiry: DateTime.utc(2027, 1, 31),
      );
      await pump(tester, c, MembershipActions(card: c));

      expect(find.text('MBR-0007'), findsOneWidget);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.textContaining('2027'), findsOneWidget);
    });

    testWidgets('renewing sends the chosen number of months', (tester) async {
      final c = base(type: 'membership', membershipNumber: 'MBR-0007');
      await pump(tester, c, MembershipActions(card: c));
      api.membershipResult = MembershipResult(
        membershipNumber: 'MBR-0007',
        membershipCategory: null,
        membershipExpiry: DateTime.utc(2027, 9, 7),
      );

      await tester.tap(find.text('12 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Renew'));
      await tester.pumpAndSettle();

      expect(api.actions, ['renewMembership:12']);
    });

    testWidgets('a card with no expiry says so rather than showing a blank', (
      tester,
    ) async {
      final c = base(type: 'membership', membershipNumber: 'MBR-0007');
      await pump(tester, c, MembershipActions(card: c));

      expect(find.text('No expiry set'), findsOneWidget);
    });
  });
}
