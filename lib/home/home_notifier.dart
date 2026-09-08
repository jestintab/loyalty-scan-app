import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models/scan_log_entry.dart';
import '../auth/auth_notifier.dart';
import '../logs/scan_log_format.dart';

/// What the home screen shows above the scan button: how the shift is going,
/// and the last few scans as proof the till is actually reaching the server.
class HomeState {
  const HomeState({
    this.loading = false,
    this.todayCount = 0,
    this.todayCountCapped = false,
    this.recent = const [],
    this.error,
  });

  final bool loading;
  final int todayCount;

  /// True when today's real total is higher than [todayCount] and cannot be
  /// known from one page. The screen says "100+" rather than a wrong number.
  final bool todayCountCapped;

  final List<ScanLogEntry> recent;
  final String? error;
}

class HomeNotifier extends Notifier<HomeState> {
  /// Enough rows to show the till is live, few enough that the scan button
  /// stays above the fold on a small phone.
  static const _recentCount = 3;

  /// The API caps a page at 100, and asking for the cap is what makes today's
  /// tally exact: the log is newest-first, so one row from an earlier day
  /// proves every one of today's rows has already been seen.
  static const _pageSize = 100;

  @override
  HomeState build() => const HomeState();

  Future<void> load() async {
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const HomeState(error: 'No shop selected. Sign in again.');
      return;
    }

    state = const HomeState(loading: true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .fetchScanLog(businessId: businessId, limit: _pageSize);

      final now = DateTime.now();
      final today = page.entries
          .where((e) => isSameLocalDay(e.loggedAt.toLocal(), now))
          .length;

      state = HomeState(
        todayCount: today,
        // Every row on the page is from today and there are more behind them,
        // so today's total runs off the end of what was fetched.
        todayCountCapped:
            page.hasMore && today > 0 && today == page.entries.length,
        recent: page.entries.take(_recentCount).toList(),
      );
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = HomeState(error: e.message);
    }
  }

  Future<void> refresh() => load();
}

final homeProvider = NotifierProvider<HomeNotifier, HomeState>(
  HomeNotifier.new,
);
