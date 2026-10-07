import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'action_flow.dart';
import 'recent_actions.dart';
import 'scan_notifier.dart';

/// What the stamp controls show and act on: a whole reward card, or one
/// service of a multi-service card.
class StampTarget {
  const StampTarget({
    required this.cardId,
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
    required this.rewardDescription,
    this.serviceId,
    this.serviceName,
    this.maxIncrement,
  });

  final String cardId;
  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;
  final String rewardDescription;

  /// Null for a reward card.
  final String? serviceId;
  final String? serviceName;

  /// The most one tap may send, or null for no limit (reward cards, as today).
  final int? maxIncrement;

  factory StampTarget.forCard(LoyaltyCard card) => StampTarget(
    cardId: card.cardId,
    stampCount: card.stampCount,
    stampsRequired: card.stampsRequired,
    rewardsAvailable: card.rewardsAvailable,
    rewardDescription: card.rewardDescription,
  );

  /// One service. The increment stops at the end of the service's cycle: past
  /// it the API resets the count, and a ladder service drops the overflow.
  /// A row sitting full starts a fresh cycle, so its cap is a whole cycle.
  factory StampTarget.forService(LoyaltyCard card, String serviceId) {
    final s = card.services.firstWhere(
      (x) => x.id == serviceId,
      orElse: () => CardService.missing(serviceId),
    );
    final remaining = s.stampsRequired - s.stampCount;
    final cycle = remaining > 0 ? remaining : s.stampsRequired;
    return StampTarget(
      cardId: card.cardId,
      stampCount: s.stampCount,
      stampsRequired: s.stampsRequired,
      rewardsAvailable: s.rewardsAvailable,
      rewardDescription: s.rewardDescription,
      serviceId: s.id,
      serviceName: s.name,
      maxIncrement: cycle < 1 ? 1 : (cycle > 100 ? 100 : cycle),
    );
  }

  /// The repeat-warning key: per service, so one service never warns about
  /// the other.
  String get guardKey => serviceId == null ? cardId : '$cardId:$serviceId';

  String named(String plain, String Function(String name) withName) =>
      serviceName == null ? plain : withName(serviceName!);
}

/// Stamp count, increment and the three reward actions, for a reward card or
/// for one chosen service. Live counts come from the scan state through
/// [targetOf], so the screen always shows what the server last said.
class StampControls extends ConsumerStatefulWidget {
  const StampControls({super.key, required this.card, required this.targetOf});

  final LoyaltyCard card;
  final StampTarget Function(LoyaltyCard card) targetOf;

  @override
  ConsumerState<StampControls> createState() => _StampControlsState();
}

class _StampControlsState extends ConsumerState<StampControls> {
  int _increment = 1;

  /// Never above the target's cap, even when an action has just moved the
  /// counts under a raised increment.
  int _shown(StampTarget t) {
    final max = t.maxIncrement;
    return max != null && _increment > max ? max : _increment;
  }

  /// One tap of + or −, from the LIVE increment rather than the value the
  /// last build captured: two taps landing before a rebuild must count twice.
  int _step(StampTarget t, int delta) {
    final next = _shown(t) + delta;
    final max = t.maxIncrement;
    if (next < 1) return 1;
    return max != null && next > max ? max : next;
  }

  Future<void> _addStamps(StampTarget t) {
    final count = _shown(t);
    return runCardAction(
      context,
      ref,
      cardId: t.guardKey,
      action: CardAction.stamps,
      proceedLabel: 'Stamp anyway',
      run: () => ref
          .read(scanProvider.notifier)
          .addStamps(count, serviceId: t.serviceId),
      confirmation: (card) {
        final u = widget.targetOf(card);
        return u.named(
          'Stamped. ${u.stampCount} of ${u.stampsRequired}.',
          (n) => '$n stamped. ${u.stampCount} of ${u.stampsRequired}.',
        );
      },
    );
  }

  Future<void> _addToRewards(StampTarget t) => runCardAction(
    context,
    ref,
    cardId: t.guardKey,
    action: CardAction.addReward,
    proceedLabel: 'Add anyway',
    run: () =>
        ref.read(scanProvider.notifier).addToRewards(serviceId: t.serviceId),
    confirmation: (card) {
      final u = widget.targetOf(card);
      return u.named(
        'Reward banked. ${u.rewardsAvailable} waiting.',
        (n) => '$n reward banked. ${u.rewardsAvailable} waiting.',
      );
    },
  );

  Future<void> _redeem(StampTarget t) => runCardAction(
    context,
    ref,
    cardId: t.guardKey,
    action: CardAction.redeem,
    proceedLabel: 'Redeem',
    // Redeeming always asks, repeat or not: it spends something the customer
    // earned and the API gives it back to nobody.
    confirmTitle: t.named('Redeem a reward?', (n) => 'Redeem a $n reward?'),
    confirmBody: 'This cannot be undone.',
    run: () => ref.read(scanProvider.notifier).redeem(serviceId: t.serviceId),
    confirmation: (card) {
      final u = widget.targetOf(card);
      return u.named(
        'Reward redeemed. ${u.rewardsAvailable} left.',
        (n) => '$n reward redeemed. ${u.rewardsAvailable} left.',
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final t = widget.targetOf(card);
    final shown = _shown(t);
    final max = t.maxIncrement;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.named(
            '${t.stampCount} / ${t.stampsRequired} stamps',
            (n) => '$n: ${t.stampCount} / ${t.stampsRequired} stamps',
          ),
          style: theme.textTheme.titleLarge,
        ),
        if (t.rewardDescription.isNotEmpty)
          Text(t.rewardDescription, style: theme.textTheme.bodyMedium),
        if (t.rewardsAvailable > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${t.rewardsAvailable} reward'
              '${t.rewardsAvailable == 1 ? '' : 's'} waiting',
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
              onPressed: shown > 1
                  ? () => setState(() => _increment = _step(t, -1))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('$shown', style: theme.textTheme.headlineSmall),
            ),
            IconButton.outlined(
              icon: const Icon(Icons.add),
              onPressed: max == null || shown < max
                  ? () => setState(() => _increment = _step(t, 1))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AsyncButton(
          label: t.named('Add Stamps', (n) => 'Add $n Stamps'),
          busy: busy,
          onPressed: () => _addStamps(t),
        ),
        const SizedBox(height: 8),
        // Not disabled on stampCount >= stampsRequired: on a multi-milestone
        // card the real threshold is the cumulative total of every rung so far,
        // and this screen is not given the milestones to compute it. The server
        // knows, and its refusal is readable.
        AsyncButton(
          label: t.named('Add to Rewards', (n) => 'Add to $n Rewards'),
          tonal: true,
          busy: busy,
          onPressed: () => _addToRewards(t),
        ),
        const SizedBox(height: 8),
        // Not disabled on rewardsAvailable == 0 either: the API also allows
        // redeeming straight off a completed card, so a 10/10 card with nothing
        // banked is legitimately redeemable.
        AsyncButton(
          label: t.named('Redeem', (n) => 'Redeem $n Reward'),
          tonal: true,
          busy: busy,
          onPressed: () => _redeem(t),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
