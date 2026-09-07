import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/token_store.dart';
import 'package:qwallet_scan/logs/logs_notifier.dart';

import '../support/fake_api_client.dart';

ScanLogEntry entry(int id, {ScanLogType type = ScanLogType.stamp}) =>
    ScanLogEntry(
      id: id,
      type: type,
      cardId: 'ABC1234567',
      staffName: 'Sam',
      customerName: 'Ali',
      stampsAdded: 1,
      stampsBefore: 0,
      stampsAfter: 1,
      loggedAt: DateTime.utc(2026, 9, 7, 10 - id),
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

  test('the first page loads with no cursor', () async {
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'),
    );

    await container.read(logsProvider.notifier).loadFirstPage();

    final state = container.read(logsProvider);
    expect(api.logCursors, [null]);
    expect(state.entries, hasLength(1));
    expect(state.hasMore, isTrue);
    expect(state.cursor, 'c1');
  });

  test(
    'loadMore appends the next page and carries the cursor forward',
    () async {
      final container = containerWith();
      api.logPages
        ..add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'))
        ..add(
          ScanLogPage(entries: [entry(2)], hasMore: false, nextCursor: null),
        );
      await container.read(logsProvider.notifier).loadFirstPage();

      await container.read(logsProvider.notifier).loadMore();

      final state = container.read(logsProvider);
      expect(api.logCursors, [null, 'c1']);
      expect(state.entries.map((e) => e.id), [1, 2]);
      expect(state.hasMore, isFalse);
    },
  );

  test('loadMore does nothing once the last page is in', () async {
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(entries: [entry(1)], hasMore: false, nextCursor: null),
    );
    await container.read(logsProvider.notifier).loadFirstPage();

    await container.read(logsProvider.notifier).loadMore();

    expect(api.logCursors, hasLength(1));
  });

  test('refresh discards what was loaded and starts again', () async {
    final container = containerWith();
    api.logPages
      ..add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'))
      ..add(ScanLogPage(entries: [entry(9)], hasMore: false, nextCursor: null));
    await container.read(logsProvider.notifier).loadFirstPage();

    await container.read(logsProvider.notifier).refresh();

    final state = container.read(logsProvider);
    expect(state.entries.map((e) => e.id), [9]);
    expect(api.logCursors, [null, null]);
  });

  test(
    'a failed first page reports the error and leaves the list empty',
    () async {
      final container = containerWith();
      api.logError = ApiException.network();

      await container.read(logsProvider.notifier).loadFirstPage();

      final state = container.read(logsProvider);
      expect(state.entries, isEmpty);
      expect(state.error, "Can't reach the server. Check your connection.");
      expect(state.loading, isFalse);
    },
  );

  test('a failed second page keeps the rows already on screen', () async {
    // Losing thirty loaded rows because page two timed out would be worse than
    // the failure itself.
    final container = containerWith();
    api.logPages.add(
      ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'),
    );
    await container.read(logsProvider.notifier).loadFirstPage();
    api.logError = ApiException.network();

    await container.read(logsProvider.notifier).loadMore();

    final state = container.read(logsProvider);
    expect(state.entries, hasLength(1));
    expect(state.error, isNotNull);
  });

  test('a 401 loading the log signs the user out', () async {
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
    api.logError = ApiException(
      ApiErrorKind.unauthorized,
      'Your session has expired. Please sign in again.',
    );

    await container.read(logsProvider.notifier).loadFirstPage();

    expect(container.read(authProvider), isA<AuthSignedOut>());
  });
}
