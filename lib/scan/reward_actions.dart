import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'scan_notifier.dart';

class RewardActions extends ConsumerStatefulWidget {
  const RewardActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<RewardActions> createState() => _RewardActionsState();
}

class _RewardActionsState extends ConsumerState<RewardActions> {
  int _increment = 1;

  Future<void> _confirmRedeem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem a reward?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(scanProvider.notifier).redeem();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${card.stampCount} / ${card.stampsRequired} stamps',
          style: theme.textTheme.titleLarge,
        ),
        if (card.rewardDescription.isNotEmpty)
          Text(card.rewardDescription, style: theme.textTheme.bodyMedium),
        if (card.rewardsAvailable > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${card.rewardsAvailable} reward'
              '${card.rewardsAvailable == 1 ? '' : 's'} waiting',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove),
              onPressed: _increment > 1
                  ? () => setState(() => _increment--)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('$_increment', style: theme.textTheme.headlineSmall),
            ),
            IconButton.outlined(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _increment++),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AsyncButton(
          label: 'Add Stamps',
          busy: busy,
          onPressed: () =>
              ref.read(scanProvider.notifier).addStamps(_increment),
        ),
        const SizedBox(height: 8),
        // Not disabled on stampCount >= stampsRequired: on a multi-milestone
        // card the real threshold is the cumulative total of every rung so far,
        // and this screen is not given the milestones to compute it. The server
        // knows, and its refusal is readable.
        AsyncButton(
          label: 'Add to Rewards',
          tonal: true,
          busy: busy,
          onPressed: () => ref.read(scanProvider.notifier).addToRewards(),
        ),
        const SizedBox(height: 8),
        // Not disabled on rewardsAvailable == 0 either: the API also allows
        // redeeming straight off a completed card, so a 10/10 card with nothing
        // banked is legitimately redeemable.
        AsyncButton(
          label: 'Redeem',
          tonal: true,
          busy: busy,
          onPressed: _confirmRedeem,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
