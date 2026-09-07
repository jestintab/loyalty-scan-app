import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/logs/logs_screen.dart';

import '../support/fake_api_client.dart';

void main() {
  late FakeApiClient api;

  /// The screen loads its first page from a post-frame callback, which runs
  /// inside pumpWidget — so the fake has to be primed before pumping, not
  /// after, or the load races an empty queue.
  Future<void> pump(
    WidgetTester tester, {
    ScanLogPage? page,
    ApiException? error,
  }) async {
    api = FakeApiClient();
    if (page != null) api.logPages.add(page);
    api.logError = error;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: const MaterialApp(home: LogsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty log says so instead of showing a blank screen', (
    tester,
  ) async {
    await pump(
      tester,
      page: const ScanLogPage(entries: [], hasMore: false, nextCursor: null),
    );

    expect(find.text('No scans yet'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry rather than looking empty', (
    tester,
  ) async {
    await pump(tester, error: ApiException.network());

    expect(
      find.text("Can't reach the server. Check your connection."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('rows show the customer and what happened', (tester) async {
    await pump(
      tester,
      page: ScanLogPage(
        entries: [
          ScanLogEntry(
            id: 1,
            type: ScanLogType.redemption,
            cardId: 'ABC1234567',
            staffName: 'Sam',
            customerName: 'Ali',
            stampsAdded: 10,
            stampsBefore: 10,
            stampsAfter: 0,
            loggedAt: DateTime.utc(2026, 9, 7, 9, 15),
          ),
        ],
        hasMore: false,
        nextCursor: null,
      ),
    );

    expect(find.text('Ali'), findsOneWidget);
    expect(find.textContaining('Reward redeemed'), findsOneWidget);
    expect(find.textContaining('Sam'), findsOneWidget);
  });
}
