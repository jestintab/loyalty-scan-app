import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'action_flow.dart';
import 'recent_actions.dart';
import 'scan_notifier.dart';

class PointsActions extends ConsumerStatefulWidget {
  const PointsActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<PointsActions> createState() => _PointsActionsState();
}

class _PointsActionsState extends ConsumerState<PointsActions> {
  final _amount = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _amount.dispose();
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final serverError = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${card.pointsBalance} points',
          style: theme.textTheme.headlineMedium,
        ),
        if (card.pointsExpiry != null)
          Text(
            'Expires ${_formatDate(card.pointsExpiry!)}',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 24),
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
        if (_localError != null || serverError != null) ...[
          const SizedBox(height: 12),
          Text(
            _localError ?? serverError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
