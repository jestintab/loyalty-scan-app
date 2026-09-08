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

  testWidgets('the identifier field says a mobile number works too', (
    tester,
  ) async {
    await pumpLogin(tester);

    // Staff can be issued a mobile and no email; a field labelled "Email" would
    // read as "you cannot sign in".
    expect(find.text('Email or mobile number'), findsOneWidget);
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
    expect(find.text('Enter your email or mobile number'), findsOneWidget);
  });
}
