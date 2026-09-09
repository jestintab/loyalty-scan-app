import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The actions a till can repeat by accident. Named, because the warning has
/// to say which one already happened.
enum CardAction {
  stamps('added stamps to'),
  addReward('banked a reward on'),
  redeem('redeemed a reward on'),
  points('changed the points on'),
  membership('renewed');

  const CardAction(this.pastTense);

  /// Reads as "You `<pastTense>` this card 20 seconds ago."
  final String pastTense;
}

/// A short memory of what was just done to which card.
///
/// The double-stamp this catches is a specific one: the till returns to the
/// dashboard the moment an action lands, so a member of staff who looks away
/// mid-tap has no screen telling them it worked, scans the same card again and
/// stamps it twice. A minute is long enough to cover that and short enough that
/// a customer buying a second coffee is not interrogated about it.
class RecentActions extends Notifier<Map<String, DateTime>> {
  static const window = Duration(minutes: 1);

  @override
  Map<String, DateTime> build() => {};

  static String _key(String cardId, CardAction action) =>
      '$cardId|${action.name}';

  /// How long ago this exact action last landed on this card, or null if it
  /// did not — or did, but longer ago than [window].
  Duration? sinceLast(String cardId, CardAction action) {
    final at = state[_key(cardId, action)];
    if (at == null) return null;
    final elapsed = DateTime.now().difference(at);
    return elapsed < window ? elapsed : null;
  }

  void record(String cardId, CardAction action) {
    final now = DateTime.now();
    state = {
      // Dropping what has aged out keeps this from growing all shift.
      for (final e in state.entries)
        if (now.difference(e.value) < window) e.key: e.value,
      _key(cardId, action): now,
    };
  }
}

final recentActionsProvider =
    NotifierProvider<RecentActions, Map<String, DateTime>>(RecentActions.new);

/// "20 seconds ago" / "a minute ago" — the warning only ever spans one minute.
String describeElapsed(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 5) return 'a moment ago';
  if (seconds < 60) return '$seconds seconds ago';
  return 'a minute ago';
}
