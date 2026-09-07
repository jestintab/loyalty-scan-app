import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

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
}
