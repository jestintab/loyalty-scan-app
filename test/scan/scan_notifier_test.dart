import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/token_store.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';
import '../support/multi_service_fixtures.dart';

LoyaltyCard rewardCard({int stampCount = 3, int rewardsAvailable = 0}) =>
    LoyaltyCard(
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

  ProviderContainer containerWith() {
    api = FakeApiClient();
    return ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        businessIdProvider.overrideWithValue('biz-1'),
      ],
    );
  }

  test('a good code loads the card', () async {
    final container = containerWith();
    api.card = rewardCard();

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    final state = container.read(scanProvider);
    expect(state, isA<ScanFound>());
    expect((state as ScanFound).card.cardId, 'ABC1234567');
    expect(api.fetchedCardIds, ['ABC1234567']);
  });

  test('an unrecognised code never reaches the API', () async {
    final container = containerWith();

    await container.read(scanProvider.notifier).lookUp('https://example.com');

    expect(api.fetchedCardIds, isEmpty);
    expect(
      (container.read(scanProvider) as ScanFailed).message,
      'That QR code is not a loyalty card.',
    );
  });

  test('a 404 says the card does not exist', () async {
    final container = containerWith();
    api.cardError = ApiException(
      ApiErrorKind.notFound,
      'No card found for this code.',
    );

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    expect(
      (container.read(scanProvider) as ScanFailed).message,
      'No card found for this code.',
    );
  });

  test('a second scan arriving mid-lookup is ignored', () async {
    // The camera re-reads the same code several times a second. Without this
    // guard, one card held up to the lens fires a lookup per frame — and once
    // actions are wired in Task 8, a stamp per frame.
    final container = containerWith();
    api.card = rewardCard();
    final gate = Completer<void>();
    api.gate = gate.future;

    final first = container.read(scanProvider.notifier).lookUp('ABC1234567');
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    gate.complete();
    await first;

    expect(api.fetchedCardIds, hasLength(1));
  });

  test('reset returns to idle so the next customer can be scanned', () async {
    final container = containerWith();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    container.read(scanProvider.notifier).reset();

    expect(container.read(scanProvider), isA<ScanIdle>());
  });

  test(
    'scanning without a chosen business fails loudly rather than silently',
    () async {
      api = FakeApiClient();
      final container = ProviderContainer.test(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue(null),
        ],
      );

      await container.read(scanProvider.notifier).lookUp('ABC1234567');

      expect(api.fetchedCardIds, isEmpty);
      expect(container.read(scanProvider), isA<ScanFailed>());
    },
  );

  test(
    'adding stamps renders what the server returned, not a local guess',
    () async {
      final container = containerWith();
      api.card = rewardCard(stampCount: 3);
      await container.read(scanProvider.notifier).lookUp('ABC1234567');
      // The server banked a milestone on the way: 3 + 2 would be 5, but it is not.
      api.actionResult = const CardActionResult(
        stampCount: 0,
        stampsRequired: 10,
        rewardsAvailable: 1,
      );

      await container.read(scanProvider.notifier).addStamps(2);

      final state = container.read(scanProvider) as ScanFound;
      expect(state.card.stampCount, 0);
      expect(state.card.rewardsAvailable, 1);
      expect(api.actions, ['addStamps:2']);
    },
  );

  test(
    "a refused action keeps the card up and shows the server's words",
    () async {
      final container = containerWith();
      api.card = rewardCard(stampCount: 3);
      await container.read(scanProvider.notifier).lookUp('ABC1234567');
      api.actionError = ApiException(
        ApiErrorKind.badRequest,
        'Stamps not yet complete (3/10)',
      );

      await container.read(scanProvider.notifier).addToRewards();

      final state = container.read(scanProvider) as ScanFound;
      expect(state.actionError, 'Stamps not yet complete (3/10)');
      expect(state.card.stampCount, 3);
      expect(state.busy, isFalse);
    },
  );

  test('a second action while one is in flight is ignored', () async {
    final container = containerWith();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionResult = const CardActionResult(
      stampCount: 4,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );
    final gate = Completer<void>();
    api.gate = gate.future;

    final first = container.read(scanProvider.notifier).addStamps(1);
    await container.read(scanProvider.notifier).addStamps(1);
    gate.complete();
    await first;

    expect(api.actions, ['addStamps:1']);
  });

  test('redeem posts and updates', () async {
    final container = containerWith();
    api.card = rewardCard(rewardsAvailable: 1);
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionResult = const CardActionResult(
      stampCount: 0,
      stampsRequired: 10,
      rewardsAvailable: 0,
    );

    await container.read(scanProvider.notifier).redeem();

    expect(api.actions, ['redeem']);
    expect(
      (container.read(scanProvider) as ScanFound).card.rewardsAvailable,
      0,
    );
  });

  test('a 401 during a lookup signs the user out', () async {
    api = FakeApiClient();
    final store = FakeTokenStore();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    await container.read(authProvider.notifier).restore();
    api.cardError = ApiException(
      ApiErrorKind.unauthorized,
      'Your session has expired. Please sign in again.',
    );

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    expect(container.read(authProvider), isA<AuthSignedOut>());
    expect(store.clearCount, 1);
  });

  test('a 400 does not sign anyone out', () async {
    // Only an expired token ends the session. A refused action is not a reason
    // to make someone sign in again mid-transaction.
    api = FakeApiClient();
    final store = FakeTokenStore();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    await container.read(authProvider.notifier).restore();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionError = ApiException(
      ApiErrorKind.badRequest,
      'Stamps not yet complete (3/10)',
    );

    await container.read(scanProvider.notifier).addToRewards();

    expect(container.read(authProvider), isA<AuthSignedIn>());
    expect(store.clearCount, 0);
  });

  group('service actions', () {
    test(
      'a stamp on one service sends its id and adopts the returned services',
      () async {
        final container = containerWith();
        api.card = multiCard();
        await container.read(scanProvider.notifier).lookUp('MSC1234567');
        api.actionResult = CardActionResult(
          stampCount: 5,
          stampsRequired: 0,
          rewardsAvailable: 1,
          services: [
            service('s1', 'Mani/Pedi', 4, 5, rewards: 1),
            service('s2', 'Blowdry', 1, 5),
          ],
        );

        final updated = await container
            .read(scanProvider.notifier)
            .addStamps(2, serviceId: 's1');

        expect(api.actions, ['addStamps:2@s1']);
        expect(updated!.services.first.stampCount, 4);
        expect(updated.stampCount, 5);
        expect(updated.templateType, 'multi_service');
        final state = container.read(scanProvider) as ScanFound;
        expect(state.card.services.first.stampCount, 4);
      },
    );

    test('the repeat memory is per service', () async {
      final container = containerWith();
      api.card = multiCard();
      await container.read(scanProvider.notifier).lookUp('MSC1234567');
      api.actionResult = CardActionResult(
        stampCount: 4,
        stampsRequired: 0,
        rewardsAvailable: 1,
        services: multiCard().services,
      );

      await container.read(scanProvider.notifier).redeem(serviceId: 's1');

      final recent = container.read(recentActionsProvider.notifier);
      expect(recent.sinceLast('MSC1234567:s1', CardAction.redeem), isNotNull);
      expect(recent.sinceLast('MSC1234567:s2', CardAction.redeem), isNull);
      expect(recent.sinceLast('MSC1234567', CardAction.redeem), isNull);
    });

    test(
      'a refused service action keeps the card and records nothing',
      () async {
        final container = containerWith();
        api.card = multiCard();
        await container.read(scanProvider.notifier).lookUp('MSC1234567');
        api.actionError = ApiException.fromResponse(
          409,
          '{"error":"Card was updated concurrently, please retry"}',
        );

        final updated = await container
            .read(scanProvider.notifier)
            .addToRewards(serviceId: 's2');

        expect(updated, isNull);
        final state = container.read(scanProvider) as ScanFound;
        expect(
          state.actionError,
          'Card was updated concurrently, please retry',
        );
        expect(state.card.services.length, 2);
        expect(
          container
              .read(recentActionsProvider.notifier)
              .sinceLast('MSC1234567:s2', CardAction.addReward),
          isNull,
        );
      },
    );
  });
}
