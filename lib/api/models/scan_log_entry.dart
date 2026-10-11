enum ScanLogType {
  stamp,
  redemption,
  checkIn,
  pointsEarn,
  pointsRedeem,
  pointsAdjust,
}

/// One row of the union of scan_log and redemption_log the API returns.
class ScanLogEntry {
  const ScanLogEntry({
    required this.id,
    required this.type,
    required this.cardId,
    required this.staffName,
    required this.customerName,
    required this.stampsAdded,
    required this.stampsBefore,
    required this.stampsAfter,
    required this.loggedAt,
    this.billAmount,
    this.itemName,
    this.rewardName,
  });

  final int id;
  final ScanLogType type;
  final String cardId;
  final String? staffName;
  final String? customerName;
  final int stampsAdded;
  final int stampsBefore;
  final int stampsAfter;
  final DateTime loggedAt;

  /// Points rows only. For points rows the stamps* numbers are points: the
  /// points earned or adjusted, and the balance before and after.
  final String? billAmount;
  final String? itemName;
  final String? rewardName;

  bool get isPoints =>
      type == ScanLogType.pointsEarn ||
      type == ScanLogType.pointsRedeem ||
      type == ScanLogType.pointsAdjust;

  factory ScanLogEntry.fromJson(Map<String, dynamic> json) => ScanLogEntry(
    id: _int(json['id']),
    type: switch (json['type']) {
      'redemption' => ScanLogType.redemption,
      'check_in' => ScanLogType.checkIn,
      'points_earn' => ScanLogType.pointsEarn,
      'points_redeem' => ScanLogType.pointsRedeem,
      'points_adjust' => ScanLogType.pointsAdjust,
      _ => ScanLogType.stamp,
    },
    cardId: (json['cardId'] as String?) ?? '',
    staffName: json['staffName'] as String?,
    customerName: json['customerName'] as String?,
    stampsAdded: _int(json['stampsAdded']),
    stampsBefore: _int(json['stampsBefore']),
    stampsAfter: _int(json['stampsAfter']),
    loggedAt:
        DateTime.tryParse(json['loggedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    // NUMERIC arrives as a string ("87.50"); tolerate a number too.
    billAmount: switch (json['billAmount']) {
      final num n => n.toStringAsFixed(2),
      final String s => s,
      _ => null,
    },
    itemName: json['itemName'] as String?,
    rewardName: json['rewardName'] as String?,
  );
}

class ScanLogPage {
  const ScanLogPage({
    required this.entries,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<ScanLogEntry> entries;
  final bool hasMore;

  /// The last row's `loggedAt`. Pass it back as `cursor` for the next page.
  final String? nextCursor;

  factory ScanLogPage.fromJson(Map<String, dynamic> json) => ScanLogPage(
    entries: ((json['scanLog'] as List?) ?? const [])
        .map((e) => ScanLogEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    hasMore: json['hasMore'] == true,
    nextCursor: json['nextCursor'] as String?,
  );
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
