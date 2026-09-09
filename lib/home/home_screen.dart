import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_notifier.dart';
import '../auth/business_name.dart';
import '../logs/scan_log_tile.dart';
import '../scan/action_message.dart';
import 'home_notifier.dart';

/// The screen a shift starts and returns to.
///
/// It answers the two things a person at a till wants without touching
/// anything — which shop they are signed into, and whether the scans they have
/// been making are actually landing — and then gets out of the way of the one
/// button that matters.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Every arrival reloads, including the one straight after an action, which
    // is how the tally stays honest without the action having to update it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeProvider.notifier).load();
      // Arriving fresh — after sign-in, or when the dashboard was not already
      // in the stack — the message was posted before this screen existed, so
      // there was no listener to hear it.
      _report(ref.read(actionMessageProvider.notifier).take());
    });
  }

  /// Raised a frame late, deliberately. A SnackBar goes to whichever Scaffold
  /// is registered with the messenger at the moment it is shown, and on the way
  /// back from an action the outgoing route is still the registered one until
  /// the transition completes. One frame is enough for this screen to be
  /// holding it instead.
  void _report(String? message) {
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Returning from an action, which is the usual case: this screen is still
    // alive, so the message arrives as a change rather than as a starting
    // value.
    ref.listen<String?>(actionMessageProvider, (_, message) {
      if (message == null) return;
      ref.read(actionMessageProvider.notifier).take();
      _report(message);
    });

    final state = ref.watch(homeProvider);
    final theme = Theme.of(context);
    final businessId = ref.watch(businessIdProvider);
    final shop = businessId == null
        ? null
        : ref.watch(businessNameProvider(businessId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(shop ?? 'Qwallet'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Today(state: state),
            const SizedBox(height: 20),
            SizedBox(
              height: 132,
              child: FilledButton.icon(
                // Never disabled by a failed or pending summary: the count is
                // a courtesy, scanning is the job.
                onPressed: () => context.push('/scan'),
                icon: const Icon(Icons.qr_code_scanner, size: 34),
                label: Text(
                  'Start scanning',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            if (state.recent.isNotEmpty) ...[
              Text('Recent', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final entry in state.recent) ScanLogTile(entry: entry),
              const SizedBox(height: 12),
            ],
            FilledButton.tonal(
              onPressed: () => context.push('/logs'),
              child: const Text('Full scan log'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.loading) {
      return Text(
        'Counting today’s scans…',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (state.error != null) {
      return Text(
        state.error!,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    final count = state.todayCount;
    final label = state.todayCountCapped
        ? '$count+ scans today'
        : '$count scan${count == 1 ? '' : 's'} today';

    return Text(
      label,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
