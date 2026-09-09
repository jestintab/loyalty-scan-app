import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models/scan_log_entry.dart';
import '../auth/auth_notifier.dart';

class LogsState {
  const LogsState({
    this.entries = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.cursor,
    this.error,
  });

  final List<ScanLogEntry> entries;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? cursor;
  final String? error;

  LogsState copyWith({
    List<ScanLogEntry>? entries,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? cursor,
    String? error,
  }) => LogsState(
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    cursor: cursor ?? this.cursor,
    error: error,
  );
}

class LogsNotifier extends Notifier<LogsState> {
  @override
  LogsState build() => const LogsState();

  Future<void> loadFirstPage() async {
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const LogsState(error: 'No shop selected. Sign in again.');
      return;
    }

    state = const LogsState(loading: true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .fetchScanLog(businessId: businessId);
      state = LogsState(
        entries: page.entries,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = LogsState(error: e.message);
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (!current.hasMore || current.loadingMore || current.cursor == null) {
      return;
    }

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) return;

    state = current.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .fetchScanLog(businessId: businessId, cursor: current.cursor);
      state = LogsState(
        entries: [...current.entries, ...page.entries],
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      // The rows already loaded stay: a failed page two must not empty the
      // screen.
      state = current.copyWith(loadingMore: false, error: e.message);
    }
  }

  Future<void> refresh() => loadFirstPage();
}

final logsProvider = NotifierProvider<LogsNotifier, LogsState>(
  LogsNotifier.new,
);
