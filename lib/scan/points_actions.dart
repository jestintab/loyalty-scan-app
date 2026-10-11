import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../api/models/points_program.dart';
import '../ui/async_button.dart';
import 'action_flow.dart';
import 'recent_actions.dart';
import 'scan_notifier.dart';

/// The points card screen. A card whose template has a points program gets
/// purchase entry (bill amount or item buttons), Redeem and Adjust; a manual
/// points card keeps the plain Add/Deduct screen it always had.
class PointsActions extends ConsumerStatefulWidget {
  const PointsActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<PointsActions> createState() => _PointsActionsState();
}

class _PointsActionsState extends ConsumerState<PointsActions> {
  final _amount = TextEditingController();
  final _bill = TextEditingController();
  int _qty = 1;
  String? _localError;

  @override
  void dispose() {
    _amount.dispose();
    _bill.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool deduct}) async {
    final parsed = int.tryParse(_amount.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _localError = 'Enter a number of points');
      return;
    }
    setState(() => _localError = null);

    await runCardAction(
      context,
      ref,
      cardId: widget.card.cardId,
      action: CardAction.points,
      proceedLabel: deduct ? 'Deduct anyway' : 'Add anyway',
      run: () => ref
          .read(scanProvider.notifier)
          .adjustPoints(deduct ? -parsed : parsed),
      confirmation: (card) =>
          '${deduct ? 'Deducted' : 'Added'} $parsed points. '
          'Balance ${card.pointsBalance}.',
    );
  }

  /// "Added 87 points. Balance 167 · Free coffee ready."
  String _earned(LoyaltyCard c) {
    final r = ref.read(scanProvider.notifier).lastPointsResult;
    final issued = r?.rewardsIssued ?? const <String>[];
    return 'Added ${r?.pointsEarned ?? 0} points. Balance ${c.pointsBalance}'
        '${issued.isEmpty ? '' : ' · ${issued.join(', ')} ready'}.';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final serverError = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final program = card.pointsProgram;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._balance(context, card, program),
        const SizedBox(height: 24),
        if (program != null) ...[
          ..._purchase(card, program, busy),
          const SizedBox(height: 16),
          ..._redeem(card, program, busy),
          const Divider(height: 32),
        ],
        ..._adjust(busy),
        if (_localError != null || serverError != null) ...[
          const SizedBox(height: 12),
          Text(
            _localError ?? serverError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  List<Widget> _balance(
    BuildContext context,
    LoyaltyCard card,
    PointsProgramView? program,
  ) {
    final theme = Theme.of(context);
    return [
      Text(
        '${card.pointsBalance} points',
        style: theme.textTheme.headlineMedium,
      ),
      if (program?.nextReward != null)
        Text(
          '${program!.nextReward!.pointsToGo} points to ${program.nextReward!.name}',
          style: theme.textTheme.bodyMedium,
        ),
      if (card.pointsExpiry != null)
        Text(
          'Expires ${_formatDate(card.pointsExpiry!)}',
          style: theme.textTheme.bodySmall,
        ),
    ];
  }

  List<Widget> _purchase(
    LoyaltyCard card,
    PointsProgramView program,
    bool busy,
  ) {
    if (program.byAmount) {
      final preview = program.pointsForAmount(_bill.text);
      return [
        TextField(
          key: const Key('points-bill'),
          controller: _bill,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: const InputDecoration(
            labelText: 'Bill amount (QAR)',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          preview == null ? 'Enter an amount' : '= $preview points',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        AsyncButton(
          label: 'Add purchase',
          busy: busy,
          onPressed: preview == null
              ? null
              : () => runCardAction(
                  context,
                  ref,
                  cardId: card.cardId,
                  action: CardAction.earnPoints,
                  proceedLabel: 'Add anyway',
                  run: () => ref
                      .read(scanProvider.notifier)
                      .earnPoints(amount: double.parse(_bill.text)),
                  confirmation: _earned,
                ),
        ),
      ];
    }
    return [
      Row(
        children: [
          const Text('Quantity'),
          IconButton(
            key: const Key('points-qty-minus'),
            onPressed: () => setState(() => _qty = (_qty - 1).clamp(1, 10)),
            icon: const Icon(Icons.remove),
          ),
          Text('$_qty'),
          IconButton(
            key: const Key('points-qty-plus'),
            onPressed: () => setState(() => _qty = (_qty + 1).clamp(1, 10)),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      for (final item in program.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncButton(
            label: '${item.name} +${item.points * _qty}',
            busy: busy,
            onPressed: () => runCardAction(
              context,
              ref,
              cardId: card.cardId,
              action: CardAction.earnPoints,
              proceedLabel: 'Add anyway',
              run: () => ref
                  .read(scanProvider.notifier)
                  .earnPoints(itemId: item.id, quantity: _qty),
              confirmation: _earned,
            ),
          ),
        ),
    ];
  }

  List<Widget> _redeem(LoyaltyCard card, PointsProgramView program, bool busy) {
    if (program.converts) {
      return [
        for (final r in program.readyRewards)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AsyncButton(
              label: 'Redeem ${r.name}',
              busy: busy,
              onPressed: () => runCardAction(
                context,
                ref,
                cardId: card.cardId,
                action: CardAction.redeem,
                proceedLabel: 'Redeem anyway',
                // By readyId: reward ids can repeat after a merchant deletes one.
                run: () => ref
                    .read(scanProvider.notifier)
                    .redeemPointsReward(readyId: r.readyId),
                confirmation: (c) => 'Redeemed ${r.name}.',
              ),
            ),
          ),
      ];
    }
    return [
      for (final r in program.rewards.where((r) => r.affordable))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncButton(
            label: 'Redeem ${r.name} (−${r.points})',
            busy: busy,
            onPressed: () => runCardAction(
              context,
              ref,
              cardId: card.cardId,
              action: CardAction.redeem,
              proceedLabel: 'Redeem anyway',
              run: () => ref
                  .read(scanProvider.notifier)
                  .redeemPointsReward(rewardId: r.id),
              confirmation: (c) =>
                  'Redeemed ${r.name}. Balance ${c.pointsBalance}.',
            ),
          ),
        ),
    ];
  }

  /// Add/Deduct by hand: the whole screen on a manual card, and the
  /// refunds-and-corrections section on a program card.
  List<Widget> _adjust(bool busy) => [
    TextField(
      key: const Key('points-amount'),
      controller: _amount,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Points',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    AsyncButton(
      label: 'Add Points',
      busy: busy,
      onPressed: () => _submit(deduct: false),
    ),
    const SizedBox(height: 8),
    AsyncButton(
      label: 'Deduct Points',
      tonal: true,
      busy: busy,
      onPressed: () => _submit(deduct: true),
    ),
  ];
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
