import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/token_store.dart';
import 'package:qwallet_scan/home/home_notifier.dart';

import '../support/fake_api_client.dart';

ScanLogEntry at(DateTime when, {int id = 1, String who = 'Ali'}) =>
    ScanLogEntry(
      id: id,
      type: ScanLogType.stamp,
      cardId: 'ABC1234567',
      staffName: 'Sam',
      customerName: who,
      stampsAdded: 1,
      stampsBefore: 0,
      stampsAfter: 1,
      loggedAt: when,
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
        businessIdProvider.overrideWithValue('biz-1'),
      ],
    );
  }

  final now = DateTime.now();
  final earlier = now.subtract(const Duration(hours: 2));
  final daysAgo = now.subtract(const Duration(days: 3));

  test("today's tally counts only today, in local time", () async {
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(
        entries: [at(now, id: 3), at(earlier, id: 2), at(daysAgo, id: 1)],
        hasMore: false,
        nextCursor: null,
      ),
    );

    await container.read(homeProvider.notifier).load();

    final state = container.read(homeProvider);
    expect(state.todayCount, 2);
    expect(state.todayCountCapped, isFalse);
  });

  test(
    'a page that is all from today, with more behind it, is capped',
    () async {
      final container = containerWith();
      api.logPages.add(
        ScanLogPage(
          entries: [at(now, id: 2), at(earlier, id: 1)],
          hasMore: true,
          nextCursor: 'c1',
        ),
      );

      await container.read(homeProvider.notifier).load();

      expect(container.read(homeProvider).todayCountCapped, isTrue);
    },
  );

  test('more pages behind older rows still gives an exact tally', () async {
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(
        entries: [at(now, id: 2), at(daysAgo, id: 1)],
        hasMore: true,
        nextCursor: 'c1',
      ),
    );

    await container.read(homeProvider.notifier).load();

    // The older row proves today's rows have all been seen, however many
    // pages remain.
    expect(container.read(homeProvider).todayCount, 1);
    expect(container.read(homeProvider).todayCountCapped, isFalse);
  });

  test('recent shows the newest few, whatever day they fall on', () async {
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(
        entries: [
          at(daysAgo, id: 4, who: 'A'),
          at(daysAgo, id: 3, who: 'B'),
          at(daysAgo, id: 2, who: 'C'),
          at(daysAgo, id: 1, who: 'D'),
        ],
        hasMore: false,
        nextCursor: null,
      ),
    );

    await container.read(homeProvider.notifier).load();

    final recent = container.read(homeProvider).recent;
    expect(recent.map((e) => e.customerName), ['A', 'B', 'C']);
  });

  test('a quiet shop reads as zero, not as an error', () async {
    final container = containerWith();
    api.logPages.add(
      const ScanLogPage(entries: [], hasMore: false, nextCursor: null),
    );

    await container.read(homeProvider.notifier).load();

    final state = container.read(homeProvider);
    expect(state.todayCount, 0);
    expect(state.todayCountCapped, isFalse);
    expect(state.error, isNull);
  });

  test('a failed load shows the message and keeps the session', () async {
    final container = containerWith();
    api.logError = ApiException.fromResponse(500, '');

    await container.read(homeProvider.notifier).load();

    expect(container.read(homeProvider).error, isNotNull);
    expect(store.clearCount, 0);
  });

  test('an expired token signs out from the home screen too', () async {
    final container = containerWith();
    api.logError = ApiException.fromResponse(401, '');

    await container.read(homeProvider.notifier).load();

    expect(container.read(authProvider), isA<AuthSignedOut>());
    expect(store.clearCount, 1);
  });
}
