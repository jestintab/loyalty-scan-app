/// Reads only the fields the counter needs. The API returns colours, image
/// URLs and custom field definitions too — this app renders none of them.
class LoyaltyCard {
  const LoyaltyCard({
    required this.cardId,
    required this.businessId,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
    required this.templateType,
    required this.stampCount,
    required this.rewardsAvailable,
    required this.stampsRequired,
    required this.rewardDescription,
    required this.businessName,
    required this.pointsBalance,
    required this.pointsExpiry,
    required this.membershipNumber,
    required this.membershipCategory,
    required this.membershipExpiry,
    this.services = const [],
  });

  final String cardId;
  final String businessId;
  final String? userName;
  final String? userEmail;
  final String? userPhone;

  /// 'reward', 'points' or 'membership'. Anything else is shown as unsupported
  /// rather than guessed at.
  final String templateType;

  final int stampCount;
  final int rewardsAvailable;

  /// The ladder total on a multi-milestone card, not the current rung. Shown,
  /// never used to decide whether an action is allowed — see the spec.
  final int stampsRequired;

  final String rewardDescription;
  final String? businessName;
  final int pointsBalance;
  final DateTime? pointsExpiry;
  final String? membershipNumber;
  final String? membershipCategory;
  final DateTime? membershipExpiry;

  /// A multi-service card's services, in the API's order (s1, s2). Empty for
  /// every other card type, and for responses from before services existed.
  final List<CardService> services;

  /// A copy carrying the counts an action returned. Only these three move —
  /// the customer and the card's identity do not change under a stamp.
  LoyaltyCard withRewardState({
    required int stampCount,
    required int rewardsAvailable,
    required int stampsRequired,
  }) => LoyaltyCard(
    cardId: cardId,
    businessId: businessId,
    userName: userName,
    userEmail: userEmail,
    userPhone: userPhone,
    templateType: templateType,
    stampCount: stampCount,
    rewardsAvailable: rewardsAvailable,
    stampsRequired: stampsRequired,
    rewardDescription: rewardDescription,
    businessName: businessName,
    pointsBalance: pointsBalance,
    pointsExpiry: pointsExpiry,
    membershipNumber: membershipNumber,
    membershipCategory: membershipCategory,
    membershipExpiry: membershipExpiry,
    services: services,
  );

  LoyaltyCard withPointsState({
    required int pointsBalance,
    required DateTime? pointsExpiry,
  }) => LoyaltyCard(
    cardId: cardId,
    businessId: businessId,
    userName: userName,
    userEmail: userEmail,
    userPhone: userPhone,
    templateType: templateType,
    stampCount: stampCount,
    rewardsAvailable: rewardsAvailable,
    stampsRequired: stampsRequired,
    rewardDescription: rewardDescription,
    businessName: businessName,
    pointsBalance: pointsBalance,
    pointsExpiry: pointsExpiry,
    membershipNumber: membershipNumber,
    membershipCategory: membershipCategory,
    membershipExpiry: membershipExpiry,
    services: services,
  );

  LoyaltyCard withMembershipState({
    required String? membershipNumber,
    required String? membershipCategory,
    required DateTime? membershipExpiry,
  }) => LoyaltyCard(
    cardId: cardId,
    businessId: businessId,
    userName: userName,
    userEmail: userEmail,
    userPhone: userPhone,
    templateType: templateType,
    stampCount: stampCount,
    rewardsAvailable: rewardsAvailable,
    stampsRequired: stampsRequired,
    rewardDescription: rewardDescription,
    businessName: businessName,
    pointsBalance: pointsBalance,
    pointsExpiry: pointsExpiry,
    membershipNumber: membershipNumber,
    membershipCategory: membershipCategory,
    membershipExpiry: membershipExpiry,
    services: services,
  );

  /// A copy carrying what a service action returned: every service's counts,
  /// and the card totals the server recomputed. The server owns all of them.
  LoyaltyCard withServiceState({
    required List<CardService> services,
    required int stampCount,
    required int rewardsAvailable,
  }) => LoyaltyCard(
    cardId: cardId,
    businessId: businessId,
    userName: userName,
    userEmail: userEmail,
    userPhone: userPhone,
    templateType: templateType,
    stampCount: stampCount,
    rewardsAvailable: rewardsAvailable,
    stampsRequired: stampsRequired,
    rewardDescription: rewardDescription,
    businessName: businessName,
    pointsBalance: pointsBalance,
    pointsExpiry: pointsExpiry,
    membershipNumber: membershipNumber,
    membershipCategory: membershipCategory,
    membershipExpiry: membershipExpiry,
    services: services,
  );

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    final merchant = ((json['merchantData'] as Map?) ?? const {})
        .cast<String, dynamic>();
    return LoyaltyCard(
      cardId: json['cardId'] as String,
      businessId: json['businessId'] as String,
      userName: json['userName'] as String?,
      userEmail: json['userEmail'] as String?,
      userPhone: json['userPhone'] as String?,
      templateType: (json['templateType'] as String?) ?? 'reward',
      stampCount: _int(json['stampCount']),
      rewardsAvailable: _int(json['rewardsAvailable']),
      stampsRequired: _int(merchant['stampsRequired']),
      rewardDescription: (merchant['rewardDescription'] as String?) ?? '',
      businessName: merchant['businessName'] as String?,
      pointsBalance: _int(json['pointsBalance']),
      pointsExpiry: _date(json['pointsExpiry']),
      membershipNumber: json['membershipNumber'] as String?,
      membershipCategory: json['membershipCategory'] as String?,
      membershipExpiry: _date(json['membershipExpiry']),
      services: _services(json['services']),
    );
  }
}

/// What every reward action returns. The screen renders these numbers rather
/// than incrementing its own — the server owns the count.
class CardActionResult {
  const CardActionResult({
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
    this.services = const [],
  });

  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;

  /// Every service of a multi-service card, as the action left them. Empty
  /// for every other card type.
  final List<CardService> services;

  factory CardActionResult.fromJson(Map<String, dynamic> json) =>
      CardActionResult(
        stampCount: _int(json['stampCount']),
        stampsRequired: _int(json['stampsRequired']),
        rewardsAvailable: _int(json['rewardsAvailable']),
        services: _services(json['services']),
      );
}

class PointsResult {
  const PointsResult({required this.pointsBalance, required this.pointsExpiry});

  final int pointsBalance;
  final DateTime? pointsExpiry;

  factory PointsResult.fromJson(Map<String, dynamic> json) => PointsResult(
    pointsBalance: _int(json['pointsBalance']),
    pointsExpiry: _date(json['pointsExpiry']),
  );
}

class MembershipResult {
  const MembershipResult({
    required this.membershipNumber,
    required this.membershipCategory,
    required this.membershipExpiry,
  });

  final String? membershipNumber;
  final String? membershipCategory;
  final DateTime? membershipExpiry;

  factory MembershipResult.fromJson(Map<String, dynamic> json) =>
      MembershipResult(
        membershipNumber: json['membershipNumber'] as String?,
        membershipCategory: json['membershipCategory'] as String?,
        membershipExpiry: _date(json['membershipExpiry']),
      );
}

/// One service of a multi-service card, as the API's serviceApiShape sends it.
/// Counts are this service's own; the card's stampCount is the total.
class CardService {
  const CardService({
    required this.id,
    required this.name,
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
    required this.stampsUntilReward,
    required this.rewardDescription,
    required this.isLadder,
  });

  final String id;
  final String name;
  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;

  /// Stamps to the next reward — the next rung on a ladder.
  final int stampsUntilReward;

  /// The reward currently on offer: the next rung's on a ladder.
  final String rewardDescription;

  /// A reward ladder banks each rung by itself as stamps land, so there is no
  /// full row waiting to be banked by hand.
  final bool isLadder;

  /// Stands in for a service the card no longer lists, so a stale selection
  /// renders zeros instead of throwing.
  factory CardService.missing(String id) => CardService(
    id: id,
    name: id,
    stampCount: 0,
    stampsRequired: 0,
    rewardsAvailable: 0,
    stampsUntilReward: 0,
    rewardDescription: '',
    isLadder: false,
  );

  factory CardService.fromJson(Map<String, dynamic> json) {
    final reward = ((json['currentReward'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final rungs = json['rewardMilestones'];
    return CardService(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? (json['id'] as String),
      stampCount: _int(json['stampCount']),
      stampsRequired: _int(json['stampsRequired']),
      rewardsAvailable: _int(json['rewardsAvailable']),
      stampsUntilReward: _int(json['stampsUntilReward']),
      rewardDescription: (reward['description'] as String?) ?? '',
      isLadder: rungs is List && rungs.length >= 2,
    );
  }
}

List<CardService> _services(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((m) => CardService.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false)
    : const [];

/// Postgres BIGINT and NUMERIC reach JSON as strings through node-postgres, and
/// a missing key reaches here as null. All three mean zero to a counter.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
