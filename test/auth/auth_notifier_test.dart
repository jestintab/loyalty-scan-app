import 'dart:async';
import 'dart:convert';

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

  // Built through fromResponse rather than by hand: a 401 is the only thing
  // the API returns for a wrong password, and hand-writing the message here is
  // what let the session-expiry wording reach the login screen unnoticed.
  test(
    'a refused sign-in blames the credentials, not an expired session',
    () async {
      final container = containerWith();
      api.loginError = ApiException.fromResponse(
        401,
        '{"error":"Invalid credentials"}',
      );

      await container.read(authProvider.notifier).signIn('sam', 'wrong');

      final error = (container.read(authProvider) as AuthSignedOut).error;
      expect(error, isNot(contains('session')));
      expect(error, contains('password'));
    },
  );

  test('an expired token still reads as an expired session', () async {
    final container = containerWith();

    await container
        .read(authProvider.notifier)
        .handleApiError(ApiException.fromResponse(401, ''));

    expect(
      (container.read(authProvider) as AuthSignedOut).error,
      'Your session has expired. Please sign in again.',
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

  group('session renewal', () {
    const storedSession = StoredAuth(
      token: 'old-jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );

    Session renewed({
      String token = 'new-jwt',
      List<String> businessIds = const ['biz-1'],
      String role = 'staff',
    }) => Session(
      token: token,
      userId: 7,
      email: null,
      name: 'Sam',
      role: role,
      businessIds: businessIds,
    );

    test('launch swaps the stored token for a fresh one', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshResult = renewed();

      await container.read(authProvider.notifier).restore();

      expect(api.refreshCalls, ['old-jwt']);
      expect(store.stored!.token, 'new-jwt');
      expect(container.read(authProvider.notifier).token, 'new-jwt');
      expect(
        (container.read(authProvider) as AuthSignedIn).auth.businessId,
        'biz-1',
      );
    });

    test('offline at launch keeps the stored session', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshError = ApiException.network();

      await container.read(authProvider.notifier).restore();

      expect(container.read(authProvider), isA<AuthSignedIn>());
      expect(store.stored!.token, 'old-jwt');
      expect(store.clearCount, 0);
    });

    test('a server error at launch keeps the stored session', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshError = ApiException.fromResponse(500, '');

      await container.read(authProvider.notifier).restore();

      expect(container.read(authProvider), isA<AuthSignedIn>());
      expect(store.clearCount, 0);
    });

    test('an already-expired session signs out and says why', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshError = ApiException.fromResponse(
        401,
        '{"error":"Invalid or expired token"}',
      );

      await container.read(authProvider.notifier).restore();

      expect(
        (container.read(authProvider) as AuthSignedOut).error,
        'Your session has expired. Please sign in again.',
      );
      expect(store.stored, isNull);
    });

    test(
      'a removed business sends a multi-business user to the picker',
      () async {
        final container = containerWith();
        store.stored = storedSession;
        api.refreshResult = renewed(businessIds: ['biz-2', 'biz-3']);

        await container.read(authProvider.notifier).restore();

        expect(container.read(authProvider), isA<AuthNeedsBusiness>());
        expect(store.stored!.businessId, isNull);
      },
    );

    test('an account unlinked from every business is signed out', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshResult = renewed(businessIds: const []);

      await container.read(authProvider.notifier).restore();

      expect(container.read(authProvider), isA<AuthSignedOut>());
      expect(store.stored, isNull);
    });

    test(
      'resuming soon after a renewal does not call the server again',
      () async {
        final container = containerWith();
        store.stored = storedSession;
        api.refreshResult = renewed();
        await container.read(authProvider.notifier).restore();

        await container.read(authProvider.notifier).renew();

        expect(api.refreshCalls, hasLength(1));
      },
    );

    test('signing out while a renewal is in flight stays signed out', () async {
      final container = containerWith();
      store.stored = storedSession;
      api.refreshResult = renewed();
      final gate = Completer<void>();
      api.gate = gate.future;

      final restoring = container.read(authProvider.notifier).restore();
      await Future<void>.delayed(Duration.zero);
      await container.read(authProvider.notifier).signOut();
      gate.complete();
      await restoring;

      expect(container.read(authProvider), isA<AuthSignedOut>());
      expect(store.stored, isNull);
    });

    test('a login stored by version 1.3.0 still reads after the update', () {
      // The exact shape 1.3.0 writes. If this stops parsing, SecureTokenStore
      // throws it away and every phone is signed out by the update.
      final restored = StoredAuth.fromJson(
        jsonDecode(
              '{"token":"t","name":"Sam","role":"staff",'
              '"businessIds":["biz-1"],"businessId":"biz-1"}',
            )
            as Map<String, dynamic>,
      );
      expect(restored.token, 't');
      expect(restored.businessId, 'biz-1');
    });
  });

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
