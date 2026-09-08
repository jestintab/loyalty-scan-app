import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models/loyalty_card.dart';
import '../auth/auth_notifier.dart';
import 'card_id_parser.dart';
import 'recent_actions.dart';

sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanLoading extends ScanState {
  const ScanLoading();
}

class ScanFound extends ScanState {
  const ScanFound(this.card, {this.actionError, this.busy = false});

  final LoyaltyCard card;

  /// The server's refusal of the last action, shown next to the buttons. Not a
  /// separate state: the card stays on screen so staff can try something else.
  final String? actionError;

  /// An action is in flight. Buttons disable, so a double tap is one stamp.
  final bool busy;

  ScanFound copyWith({LoyaltyCard? card, String? actionError, bool? busy}) =>
      ScanFound(
        card ?? this.card,
        actionError: actionError,
        busy: busy ?? this.busy,
      );
}

class ScanFailed extends ScanState {
  const ScanFailed(this.message);
  final String message;
}

class ScanNotifier extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  /// Guards against the camera firing the same code every frame. Checked and
  /// set synchronously, before the first await, so two calls in one microtask
  /// cannot both pass.
  bool _inFlight = false;

  Future<void> lookUp(String raw) async {
    if (_inFlight) return;

    final cardId = parseCardId(raw);
    if (cardId == null) {
      state = const ScanFailed('That QR code is not a loyalty card.');
      return;
    }

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
    }

    _inFlight = true;
    state = const ScanLoading();
    try {
      final card = await ref
          .read(apiClientProvider)
          .fetchCard(cardId: cardId, businessId: businessId);
      state = ScanFound(card);
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFailed(e.message);
    } finally {
      _inFlight = false;
    }
  }

  Future<LoyaltyCard?> addStamps(int increment) => _act(
    CardAction.stamps,
    (api, card, businessId) => api.addStamps(
      cardId: card.cardId,
      businessId: businessId,
      increment: increment,
    ),
  );

  Future<LoyaltyCard?> addToRewards() => _act(
    CardAction.addReward,
    (api, card, businessId) =>
        api.addToRewards(cardId: card.cardId, businessId: businessId),
  );

  Future<LoyaltyCard?> redeem() => _act(
    CardAction.redeem,
    (api, card, businessId) =>
        api.redeem(cardId: card.cardId, businessId: businessId),
  );

  /// The shape every reward action takes: only from a loaded card, only one at
  /// a time, and the new counts come from the response — never from arithmetic
  /// here. A multi-milestone card can bank a reward and reset to zero on an
  /// ordinary stamp, which no local guess would predict.
  ///
  /// Returns the updated card, or null if the action did not land — the button
  /// needs to tell the two apart, since only a success reports and leaves the
  /// screen. Recording the action for the repeat warning happens here rather
  /// than at the button, so a refusal is never remembered as something done.
  Future<LoyaltyCard?> _act(
    CardAction action,
    Future<CardActionResult> Function(ApiClient, LoyaltyCard, String) call,
  ) async {
    final current = state;
    if (current is! ScanFound || current.busy) return null;

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return null;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await call(
        ref.read(apiClientProvider),
        current.card,
        businessId,
      );
      final updated = current.card.withRewardState(
        stampCount: result.stampCount,
        rewardsAvailable: result.rewardsAvailable,
        stampsRequired: result.stampsRequired,
      );
      ref.read(recentActionsProvider.notifier).record(updated.cardId, action);
      state = ScanFound(updated);
      return updated;
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFound(current.card, actionError: e.message);
      return null;
    }
  }

  /// [points] is signed: the Deduct button passes a negative.
  Future<LoyaltyCard?> adjustPoints(int points) async {
    final current = state;
    if (current is! ScanFound || current.busy) return null;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return null;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await ref
          .read(apiClientProvider)
          .adjustPoints(
            cardId: current.card.cardId,
            businessId: businessId,
            points: points,
          );
      final updated = current.card.withPointsState(
        pointsBalance: result.pointsBalance,
        pointsExpiry: result.pointsExpiry,
      );
      ref
          .read(recentActionsProvider.notifier)
          .record(updated.cardId, CardAction.points);
      state = ScanFound(updated);
      return updated;
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFound(current.card, actionError: e.message);
      return null;
    }
  }

  Future<LoyaltyCard?> renewMembership(int months) async {
    final current = state;
    if (current is! ScanFound || current.busy) return null;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return null;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await ref
          .read(apiClientProvider)
          .renewMembership(
            cardId: current.card.cardId,
            businessId: businessId,
            expiryMonths: months,
          );
      final updated = current.card.withMembershipState(
        membershipNumber: result.membershipNumber,
        membershipCategory: result.membershipCategory,
        membershipExpiry: result.membershipExpiry,
      );
      ref
          .read(recentActionsProvider.notifier)
          .record(updated.cardId, CardAction.membership);
      state = ScanFound(updated);
      return updated;
    } on ApiException catch (e) {
      await ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFound(current.card, actionError: e.message);
      return null;
    }
  }

  void reset() => state = const ScanIdle();
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(
  ScanNotifier.new,
);
