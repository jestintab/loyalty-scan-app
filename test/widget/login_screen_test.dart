import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/session.dart';
import 'package:qwallet_scan/auth/login_screen.dart';
import 'package:qwallet_scan/auth/token_store.dart';

import '../support/fake_api_client.dart';

void main() {
  late FakeApiClient api;
  late FakeTokenStore store;

  Future<void> pumpLogin(WidgetTester tester) async {
    api = FakeApiClient();
    store = FakeTokenStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
  }

  testWidgets('both ways in are offered before anything is typed', (
    tester,
  ) async {
    await pumpLogin(tester);

    // Staff can be issued a mobile and no email. The old single field took
    // either but said so only in its label, leaving the person to work out
    // that a phone number was allowed at all.
    expect(
      find.widgetWithText(SegmentedButton<SignInWith>, 'Email'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SegmentedButton<SignInWith>, 'Mobile'),
      findsOneWidget,
    );
    // Email is the opening state, so no country picker yet.
    expect(find.byKey(const Key('dial')), findsNothing);
  });

  testWidgets('choosing Mobile brings out the country picker', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dial')), findsOneWidget);
    // Qatar, because that is where the tills are.
    expect(find.text('🇶🇦 +974'), findsWidgets);
  });

  testWidgets('a mobile is sent as E.164, not as it was typed', (tester) async {
    await pumpLogin(tester);
    api.loginResult = const Session(
      token: 'jwt',
      userId: 7,
      email: 's@x.qa',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
    );

    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('identifier')), '3312 3456');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The picker exists so this can be built rather than typed, and E.164 is
    // the form the accounts are stored in.
    expect(api.loginCalls.single.identifier, '+97433123456');
  });

  testWidgets("a number that breaks its country's rule never reaches the API", (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    // Seven digits; Qatar issues eight.
    await tester.enterText(find.byKey(const Key('identifier')), '3312345');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.loginCalls, isEmpty);
    expect(find.text('Enter a valid mobile number'), findsOneWidget);
  });

  testWidgets('switching back clears what belonged to the other field', (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.enterText(find.byKey(const Key('identifier')), 'sam@shop.qa');
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();

    // An email left sitting in a field now labelled "Mobile number" would be
    // submitted as one.
    expect(find.text('sam@shop.qa'), findsNothing);
  });

  testWidgets('signing in sends what was typed', (tester) async {
    await pumpLogin(tester);
    api.loginResult = const Session(
      token: 'jwt',
      userId: 7,
      email: 's@x.qa',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
    );

    await tester.enterText(find.byKey(const Key('identifier')), 'sam@shop.qa');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.loginCalls.single.identifier, 'sam@shop.qa');
    expect(api.loginCalls.single.password, 'pw');
  });

  testWidgets('a failure is shown on the screen, not swallowed', (
    tester,
  ) async {
    await pumpLogin(tester);
    // fromResponse, not a hand-written message: the screen has to show what a
    // real refusal actually produces.
    api.loginError = ApiException.fromResponse(
      401,
      '{"error":"Invalid credentials"}',
    );

    await tester.enterText(find.byKey(const Key('identifier')), 'sam');
    await tester.enterText(find.byKey(const Key('password')), 'no');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Check the email or mobile number'),
      findsOneWidget,
    );
  });

  testWidgets('empty fields are refused without calling the API', (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.loginCalls, isEmpty);
    expect(find.text('Enter your email'), findsOneWidget);
  });
}
