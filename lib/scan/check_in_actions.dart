import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/check_in_summary.dart';
import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'action_flow.dart';
import 'recent_actions.dart';
import 'scan_notifier.dart';

/// Check in a membership card. Every tap is a visit; the repeat warning in
/// runCardAction catches an accidental second scan within a minute.
class CheckInActions extends ConsumerWidget {
  const CheckInActions({super.key, required this.card});

  final LoyaltyCard card;

  static String visitLine(CheckInSummary? s) {
    if (s == null || s.visits == 0) return 'First visit';
    final last = s.lastCheckInAt?.toLocal();
    if (last == null) return 'Visit ${s.visits}';
    final hh = last.hour.toString().padLeft(2, '0');
    final mm = last.minute.toString().padLeft(2, '0');
    return 'Visit ${s.visits} · last ${last.day}/${last.month} $hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final current = state is ScanFound ? state.card : card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(visitLine(current.checkIn), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        AsyncButton(
          label: 'Check in',
          busy: busy,
          onPressed: () => runCardAction(
            context,
            ref,
            cardId: card.cardId,
            action: CardAction.checkIn,
            proceedLabel: 'Check in anyway',
            run: () => ref.read(scanProvider.notifier).checkIn(),
            confirmation: (c) => 'Checked in. Visit ${c.checkIn?.visits ?? 1}.',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
