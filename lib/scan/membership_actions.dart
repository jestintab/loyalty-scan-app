import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'scan_notifier.dart';

class MembershipActions extends ConsumerStatefulWidget {
  const MembershipActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<MembershipActions> createState() => _MembershipActionsState();
}

class _MembershipActionsState extends ConsumerState<MembershipActions> {
  static const _options = [3, 6, 12];
  int _months = 3;

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
          card.membershipNumber ?? 'No membership number',
          style: theme.textTheme.headlineSmall,
        ),
        if (card.membershipCategory != null)
          Text(card.membershipCategory!, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          card.membershipExpiry == null
              ? 'No expiry set'
              : 'Expires ${_formatDate(card.membershipExpiry!)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Text('Renew for', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final months in _options)
              ChoiceChip(
                label: Text('$months months'),
                selected: _months == months,
                onSelected: (_) => setState(() => _months = months),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(
          label: 'Renew',
          busy: busy,
          onPressed: () =>
              ref.read(scanProvider.notifier).renewMembership(_months),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
