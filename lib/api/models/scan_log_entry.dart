enum ScanLogType { stamp, redemption }

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

  factory ScanLogEntry.fromJson(Map<String, dynamic> json) => ScanLogEntry(
    id: _int(json['id']),
    type: json['type'] == 'redemption'
        ? ScanLogType.redemption
        : ScanLogType.stamp,
    cardId: (json['cardId'] as String?) ?? '',
    staffName: json['staffName'] as String?,
    customerName: json['customerName'] as String?,
    stampsAdded: _int(json['stampsAdded']),
    stampsBefore: _int(json['stampsBefore']),
    stampsAfter: _int(json['stampsAfter']),
    loggedAt:
        DateTime.tryParse(json['loggedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
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
