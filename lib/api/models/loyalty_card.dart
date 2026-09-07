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

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    final merchant =
        ((json['merchantData'] as Map?) ?? const {}).cast<String, dynamic>();
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
  });

  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;

  factory CardActionResult.fromJson(Map<String, dynamic> json) =>
      CardActionResult(
        stampCount: _int(json['stampCount']),
        stampsRequired: _int(json['stampsRequired']),
        rewardsAvailable: _int(json['rewardsAvailable']),
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
