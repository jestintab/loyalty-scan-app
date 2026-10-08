import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';
import '../ui/message_view.dart';
import 'check_in_actions.dart';
import 'membership_actions.dart';
import 'multi_service_actions.dart';
import 'points_actions.dart';
import 'reward_actions.dart';

/// The customer, then whatever can be done for their card type.
class CardResultView extends StatelessWidget {
  const CardResultView({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          card.userName?.trim().isNotEmpty == true
              ? card.userName!
              : 'Customer',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (card.userEmail != null)
          Text(card.userEmail!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        switch (card.templateType) {
          'reward' => RewardActions(card: card),
          'multi_service' => MultiServiceActions(card: card),
          'points' => PointsActions(card: card),
          'membership' => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (card.checkIn != null) ...[
                CheckInActions(card: card),
                const Divider(height: 32),
              ],
              MembershipActions(card: card, showError: card.checkIn == null),
            ],
          ),
          _ => const MessageView(
            icon: Icons.help_outline,
            title: "This card type isn't supported in this app",
            detail: 'Use the web dashboard for this customer.',
          ),
        },
      ],
    );
  }
}
