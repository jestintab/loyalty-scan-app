import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/home/home_screen.dart';

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

  Future<void> pump(WidgetTester tester, ScanLogPage page) async {
    api = FakeApiClient();
    // Primed before pumping: the screen loads in a post-frame callback, so a
    // fake filled in afterwards would be empty by the time it is read.
    api.logPages.add(page);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
              GoRoute(
                path: '/scan',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Camera'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the shop and counts the day', (tester) async {
    final now = DateTime.now();
    await pump(
      tester,
      ScanLogPage(
        entries: [at(now, id: 2), at(now, id: 1)],
        hasMore: false,
        nextCursor: null,
      ),
    );

    expect(find.text('Test Shop'), findsOneWidget);
    expect(find.text('2 scans today'), findsOneWidget);
  });

  testWidgets('one scan is not "1 scans"', (tester) async {
    await pump(
      tester,
      ScanLogPage(
        entries: [at(DateTime.now())],
        hasMore: false,
        nextCursor: null,
      ),
    );

    expect(find.text('1 scan today'), findsOneWidget);
  });

  testWidgets('a day that runs past one page says so', (tester) async {
    final now = DateTime.now();
    await pump(
      tester,
      ScanLogPage(
        entries: [at(now, id: 2), at(now, id: 1)],
        hasMore: true,
        nextCursor: 'c1',
      ),
    );

    expect(find.text('2+ scans today'), findsOneWidget);
  });

  testWidgets('the last few scans are listed', (tester) async {
    await pump(
      tester,
      ScanLogPage(
        entries: [at(DateTime.now(), who: 'Mohamad Ali')],
        hasMore: false,
        nextCursor: null,
      ),
    );

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Mohamad Ali'), findsOneWidget);
  });

  testWidgets('Start scanning opens the camera', (tester) async {
    await pump(
      tester,
      const ScanLogPage(entries: [], hasMore: false, nextCursor: null),
    );

    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('a summary that fails still lets someone scan', (tester) async {
    api = FakeApiClient();
    api.logError = ApiException.fromResponse(500, '');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
              GoRoute(
                path: '/scan',
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Camera'))),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The count is a courtesy; the button is the job.
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
  });
}
