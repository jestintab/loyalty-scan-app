import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models/loyalty_card.dart';
import 'recent_actions.dart';

/// One card action, from the button press to the till being ready for the next
/// customer.
///
/// Every action takes the same shape, so they are all run through here: warn if
/// this is a repeat, do it, say what happened, and hand the screen back to the
/// dashboard. Nobody reads a results screen at a counter — they look up at the
/// customer — so the confirmation is a snackbar, which outlives the route it
/// was raised from, and the till returns to the one button it exists for.
///
/// A refusal keeps the card on screen instead: the error is already rendered
/// there, and leaving would hide it.
Future<void> runCardAction(
  BuildContext context,
  WidgetRef ref, {
  required String cardId,
  required CardAction action,
  required String proceedLabel,
  required Future<LoyaltyCard?> Function() run,
  required String Function(LoyaltyCard) confirmation,
  String? confirmTitle,
  String? confirmBody,
}) async {
  final since = ref
      .read(recentActionsProvider.notifier)
      .sinceLast(cardId, action);

  // A repeat warning replaces the action's ordinary confirmation rather than
  // stacking on top of it — it asks the same question with more information.
  final title = since != null ? 'Already done' : confirmTitle;
  final body = since != null
      ? 'You ${action.pastTense} this card ${describeElapsed(since)}. '
            'Do it again?'
      : confirmBody;

  if (title != null) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(proceedLabel),
          ),
        ],
      ),
    );
    if (proceed != true) return;
  }

  final card = await run();
  if (card == null || !context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(confirmation(card)),
      behavior: SnackBarBehavior.floating,
    ),
  );
  context.go('/home');
}
