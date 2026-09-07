import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';

class RewardActions extends StatelessWidget {
  const RewardActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
