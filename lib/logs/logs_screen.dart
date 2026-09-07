import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/scan_log_entry.dart';
import '../ui/message_view.dart';
import 'logs_notifier.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(logsProvider.notifier).loadFirstPage();
    });
    _scroll.addListener(() {
      // 400px of runway, so the next page is usually in before the list ends.
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        ref.read(logsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan log')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(logsProvider.notifier).refresh(),
        child: switch (state) {
          LogsState(loading: true) => const Center(
            child: CircularProgressIndicator(),
          ),
          LogsState(entries: [], error: final e?) => MessageView(
            icon: Icons.cloud_off,
            title: e,
            onRetry: () => ref.read(logsProvider.notifier).loadFirstPage(),
          ),
          LogsState(entries: []) => const MessageView(
            icon: Icons.receipt_long,
            title: 'No scans yet',
            detail: 'Stamps and redemptions will appear here.',
          ),
          _ => _list(state),
        },
      ),
    );
  }

  Widget _list(LogsState state) {
    final rows = _withDayHeaders(state.entries);

    return ListView.builder(
      controller: _scroll,
      itemCount: rows.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final row = rows[i];
        return switch (row) {
          _DayHeader(:final label) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          _EntryRow(:final entry) => ListTile(
            leading: Icon(
              entry.type == ScanLogType.redemption
                  ? Icons.redeem
                  : Icons.check_circle_outline,
            ),
            title: Text(entry.customerName ?? 'Customer'),
            subtitle: Text(
              '${entry.type == ScanLogType.redemption ? 'Reward redeemed' : '+${entry.stampsAdded} stamps'}'
              ' · ${entry.stampsBefore} → ${entry.stampsAfter}'
              '${entry.staffName != null ? ' · ${entry.staffName}' : ''}',
            ),
            trailing: Text(_formatTime(entry.loggedAt.toLocal())),
          ),
        };
      },
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DayHeader extends _Row {
  const _DayHeader(this.label);
  final String label;
}

class _EntryRow extends _Row {
  const _EntryRow(this.entry);
  final ScanLogEntry entry;
}

/// Splits a flat, newest-first list into day sections. Dates are compared in
/// local time, which is what "today" means to the person reading.
List<_Row> _withDayHeaders(List<ScanLogEntry> entries) {
  final rows = <_Row>[];
  String? lastDay;
  for (final entry in entries) {
    final local = entry.loggedAt.toLocal();
    final day = '${local.year}-${local.month}-${local.day}';
    if (day != lastDay) {
      rows.add(_DayHeader(_formatDay(local)));
      lastDay = day;
    }
    rows.add(_EntryRow(entry));
  }
  return rows;
}

String _formatDay(DateTime d) {
  final now = DateTime.now();
  final isToday =
      d.year == now.year && d.month == now.month && d.day == now.day;
  if (isToday) return 'Today';

  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      d.year == yesterday.year &&
      d.month == yesterday.month &&
      d.day == yesterday.day;
  if (isYesterday) return 'Yesterday';

  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
