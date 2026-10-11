/// A points card's program as the API presents it (GET /api/passes/:cardId
/// and every points action). The app shows it; it never recomputes the rules
/// — except the "= N points" preview, which uses the API's integer-cents
/// maths so the preview and the result always agree.
class PointsItem {
  const PointsItem({
    required this.id,
    required this.name,
    required this.points,
  });
  final String id;
  final String name;
  final int points;
}

class PointsReward {
  const PointsReward({
    required this.id,
    required this.name,
    required this.points,
    required this.affordable,
  });
  final String id;
  final String name;
  final int points;
  final bool affordable;
}

/// One issued reward waiting on a convert-mode card. [readyId] is its own id:
/// reward ids are kept by position and can repeat after a merchant deletes a
/// reward, so redeeming always names the ready reward, not the reward.
class ReadyReward {
  const ReadyReward({
    required this.readyId,
    required this.rewardId,
    required this.name,
  });
  final String readyId;
  final String rewardId;
  final String name;

  static List<ReadyReward> listFrom(Object? json) => json is List
      ? json
            .whereType<Map>()
            .map(
              (m) => ReadyReward(
                readyId: '${m['readyId'] ?? ''}',
                rewardId: '${m['rewardId'] ?? ''}',
                name: '${m['name'] ?? ''}',
              ),
            )
            .toList()
      : const [];
}

class NextReward {
  const NextReward({
    required this.id,
    required this.name,
    required this.pointsToGo,
  });
  final String id;
  final String name;
  final int pointsToGo;
}

int _asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class PointsProgramView {
  const PointsProgramView({
    required this.earnMethod,
    required this.rate,
    required this.items,
    required this.mode,
    required this.rewards,
    required this.readyRewards,
    required this.nextReward,
  });

  final String earnMethod;
  final double? rate;
  final List<PointsItem> items;
  final String mode;
  final List<PointsReward> rewards;
  final List<ReadyReward> readyRewards;
  final NextReward? nextReward;

  bool get byAmount => earnMethod == 'amount';
  bool get converts => mode == 'convert';

  static PointsProgramView? fromJson(Object? json) {
    if (json is! Map) return null;
    final earn = (json['earn'] as Map?) ?? const {};
    final next = json['nextReward'];
    return PointsProgramView(
      earnMethod: '${earn['method'] ?? 'amount'}',
      rate: earn['rate'] is num ? (earn['rate'] as num).toDouble() : null,
      items: (earn['items'] is List ? earn['items'] as List : const [])
          .whereType<Map>()
          .map(
            (m) => PointsItem(
              id: '${m['id']}',
              name: '${m['name']}',
              points: _asInt(m['points']),
            ),
          )
          .toList(),
      mode: '${json['mode'] ?? 'convert'}',
      rewards: (json['rewards'] is List ? json['rewards'] as List : const [])
          .whereType<Map>()
          .map(
            (m) => PointsReward(
              id: '${m['id']}',
              name: '${m['name']}',
              points: _asInt(m['points']),
              affordable: m['affordable'] == true,
            ),
          )
          .toList(),
      readyRewards: ReadyReward.listFrom(json['readyRewards']),
      nextReward: next is Map
          ? NextReward(
              id: '${next['id']}',
              name: '${next['name']}',
              pointsToGo: _asInt(next['pointsToGo']),
            )
          : null,
    );
  }

  /// Points a bill earns, or null for an invalid amount. Integer cents, floored.
  int? pointsForAmount(String text) {
    final t = text.trim();
    if (rate == null || !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
    final cents = (double.parse(t) * 100).round();
    if (cents <= 0 || cents > 10000000) return null;
    return (cents * (rate! * 100).round()) ~/ 10000;
  }
}
