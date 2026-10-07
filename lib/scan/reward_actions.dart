import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';
import 'stamp_controls.dart';

/// A reward card's stamp and reward actions — the whole card is the target.
class RewardActions extends StatelessWidget {
  const RewardActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) =>
      StampControls(card: card, targetOf: StampTarget.forCard);
}
