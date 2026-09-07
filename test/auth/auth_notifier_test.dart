import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/session.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/token_store.dart';

import '../support/fake_api_client.dart';

Session sessionWith({
  String role = 'staff',
  List<String> businessIds = const ['biz-1'],
}) => Session(
  token: 'jwt',
  userId: 7,
  email: 's@x.qa',
  name: 'Sam',
  role: role,
  businessIds: businessIds,
);

void main() {
  late FakeApiClient api;
  late FakeTokenStore store;

  ProviderContainer containerWith() {
    api = FakeApiClient();
    store = FakeTokenStore();
    return ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
  }

  test(
    'a staff member with one business lands signed in on that business',
    () async {
      final container = containerWith();
      api.loginResult = sessionWith(businessIds: ['biz-1']);

      await container.read(authProvider.notifier).signIn('sam', 'pw');

      final state = container.read(authProvider);
      expect(state, isA<AuthSignedIn>());
      expect((state as AuthSignedIn).auth.businessId, 'biz-1');
      expect(store.stored!.token, 'jwt');
    },
  );

  test('two businesses stop at the picker rather than guessing', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: ['biz-1', 'biz-2']);

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    expect(container.read(authProvider), isA<AuthNeedsBusiness>());
  });

  test('choosing a business completes the sign-in and persists it', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: ['biz-1', 'biz-2']);
    await container.read(authProvider.notifier).signIn('sam', 'pw');

    await container.read(authProvider.notifier).chooseBusiness('biz-2');

    expect(
      (container.read(authProvider) as AuthSignedIn).auth.businessId,
      'biz-2',
    );
    expect(store.stored!.businessId, 'biz-2');
  });

  test('a customer account is refused and nothing is stored', () async {
    final container = containerWith();
    api.loginResult = sessionWith(role: 'customer');

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    final state = container.read(authProvider);
    expect(state, isA<AuthSignedOut>());
    expect(
      (state as AuthSignedOut).error,
      'This app is for staff and business owners.',
    );
    expect(store.stored, isNull);
  });

  test(
    'an account linked to no business says so, and stores nothing',
    () async {
      final container = containerWith();
      api.loginResult = sessionWith(businessIds: const []);

      await container.read(authProvider.notifier).signIn('sam', 'pw');

      final state = container.read(authProvider);
      expect(state, isA<AuthSignedOut>());
      expect(
        (state as AuthSignedOut).error,
        'This account is not linked to a business. Ask the owner to add you.',
      );
      expect(store.stored, isNull);
    },
  );

  test('bad credentials surface the API message', () async {
    final container = containerWith();
    api.loginError = ApiException(
      ApiErrorKind.unauthorized,
      'Invalid credentials',
    );

    await container.read(authProvider.notifier).signIn('sam', 'wrong');

    expect(
      (container.read(authProvider) as AuthSignedOut).error,
      'Invalid credentials',
    );
  });

  test('restore brings back a completed session', () async {
    final container = containerWith();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );

    await container.read(authProvider.notifier).restore();

    expect(container.read(authProvider), isA<AuthSignedIn>());
  });

  test('restore with no stored business returns to the picker', () async {
    final container = containerWith();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1', 'biz-2'],
      businessId: null,
    );

    await container.read(authProvider.notifier).restore();

    expect(container.read(authProvider), isA<AuthNeedsBusiness>());
  });

  test(
    'restore with nothing stored is signed out, with no error shown',
    () async {
      final container = containerWith();

      await container.read(authProvider.notifier).restore();

      final state = container.read(authProvider);
      expect(state, isA<AuthSignedOut>());
      expect((state as AuthSignedOut).error, isNull);
    },
  );

  test('signing out clears the token and can carry a reason', () async {
    final container = containerWith();
    api.loginResult = sessionWith();
    await container.read(authProvider.notifier).signIn('sam', 'pw');

    await container
        .read(authProvider.notifier)
        .signOut(reason: 'Session expired');

    expect(store.clearCount, 1);
    expect(
      (container.read(authProvider) as AuthSignedOut).error,
      'Session expired',
    );
  });
}
