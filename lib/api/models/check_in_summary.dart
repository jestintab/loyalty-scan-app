/// A membership card's check-ins: how many, and the latest. The server's
/// count, including any visit just recorded.
class CheckInSummary {
  const CheckInSummary({required this.visits, required this.lastCheckInAt});

  final int visits;
  final DateTime? lastCheckInAt;

  static CheckInSummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final visits = json['visits'];
    return CheckInSummary(
      visits: visits is num ? visits.toInt() : int.tryParse('$visits') ?? 0,
      lastCheckInAt: DateTime.tryParse(json['lastCheckInAt'] as String? ?? ''),
    );
  }
}
