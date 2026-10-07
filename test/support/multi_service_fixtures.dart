import 'package:qwallet_scan/api/models/loyalty_card.dart';

CardService service(
  String id,
  String name,
  int count,
  int required, {
  int rewards = 0,
  bool ladder = false,
}) => CardService(
  id: id,
  name: name,
  stampCount: count,
  stampsRequired: required,
  rewardsAvailable: rewards,
  stampsUntilReward: required - count > 0 ? required - count : 0,
  rewardDescription: 'Free $name',
  isLadder: ladder,
);

/// The Runway card: Mani/Pedi 2 of 5 with a reward waiting, Blowdry 1 of 5.
LoyaltyCard multiCard({List<CardService>? services}) => LoyaltyCard(
  cardId: 'MSC1234567',
  businessId: 'biz-1',
  userName: 'Mithayel',
  userEmail: null,
  userPhone: null,
  templateType: 'multi_service',
  stampCount: 3,
  rewardsAvailable: 1,
  stampsRequired: 0,
  rewardDescription: '',
  businessName: 'Runway',
  pointsBalance: 0,
  pointsExpiry: null,
  membershipNumber: null,
  membershipCategory: null,
  membershipExpiry: null,
  services:
      services ??
      [
        service('s1', 'Mani/Pedi', 2, 5, rewards: 1),
        service('s2', 'Blowdry', 1, 5),
      ],
);
