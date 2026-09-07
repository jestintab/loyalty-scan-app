import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';

class MembershipActions extends StatelessWidget {
  const MembershipActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
