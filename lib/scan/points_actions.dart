import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';

class PointsActions extends StatelessWidget {
  const PointsActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
