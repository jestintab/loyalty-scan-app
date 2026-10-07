import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import 'scan_notifier.dart';
import 'stamp_controls.dart';

/// A multi-service card at the counter: every service's progress, then a
/// service picker with NOTHING chosen. Controls appear only once staff pick
/// one — defaulting to the first would make the wrong-service stamp the easy
/// one, and the server cannot tell a mistaken stamp from a real one.
class MultiServiceActions extends ConsumerStatefulWidget {
  const MultiServiceActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<MultiServiceActions> createState() =>
      _MultiServiceActionsState();
}

class _MultiServiceActionsState extends ConsumerState<MultiServiceActions> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);
    final selected = _selectedId;

    if (card.services.isEmpty) {
      return const Text('This card has no services.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a service', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, s) in card.services.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ServiceTile(
                  service: s,
                  selected: s.id == selected,
                  onTap: () => setState(() => _selectedId = s.id),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        if (selected == null)
          Text(
            'Pick the service the customer had.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else
          // Keyed by service so switching starts its increment back at one.
          StampControls(
            key: ValueKey(selected),
            card: card,
            targetOf: (c) => StampTarget.forService(c, selected),
          ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final CardService service;
  final bool selected;
  final VoidCallback onTap;

  String get _status {
    final n = service.rewardsAvailable;
    if (n > 0) return '$n reward${n == 1 ? '' : 's'} waiting';
    if (!service.isLadder && service.stampCount >= service.stampsRequired) {
      return 'Reward ready';
    }
    return '${service.stampsUntilReward} more to reward';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rewardish = service.rewardsAvailable > 0 || _status == 'Reward ready';

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          key: Key('service-${service.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${service.stampCount} / ${service.stampsRequired}',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  _status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: rewardish ? scheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
