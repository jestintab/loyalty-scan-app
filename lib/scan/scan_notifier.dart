import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models/loyalty_card.dart';
import '../auth/auth_notifier.dart';
import 'card_id_parser.dart';

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
      state = ScanFailed(e.message);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> addStamps(int increment) => _act(
    (api, card, businessId) => api.addStamps(
      cardId: card.cardId,
      businessId: businessId,
      increment: increment,
    ),
  );

  Future<void> addToRewards() => _act(
    (api, card, businessId) =>
        api.addToRewards(cardId: card.cardId, businessId: businessId),
  );

  Future<void> redeem() => _act(
    (api, card, businessId) =>
        api.redeem(cardId: card.cardId, businessId: businessId),
  );

  /// The shape every reward action takes: only from a loaded card, only one at
  /// a time, and the new counts come from the response — never from arithmetic
  /// here. A multi-milestone card can bank a reward and reset to zero on an
  /// ordinary stamp, which no local guess would predict.
  Future<void> _act(
    Future<CardActionResult> Function(ApiClient, LoyaltyCard, String) call,
  ) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await call(
        ref.read(apiClientProvider),
        current.card,
        businessId,
      );
      state = ScanFound(
        current.card.withRewardState(
          stampCount: result.stampCount,
          rewardsAvailable: result.rewardsAvailable,
          stampsRequired: result.stampsRequired,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }

  /// [points] is signed: the Deduct button passes a negative.
  Future<void> adjustPoints(int points) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
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
      state = ScanFound(
        current.card.withPointsState(
          pointsBalance: result.pointsBalance,
          pointsExpiry: result.pointsExpiry,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }

  Future<void> renewMembership(int months) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
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
      state = ScanFound(
        current.card.withMembershipState(
          membershipNumber: result.membershipNumber,
          membershipCategory: result.membershipCategory,
          membershipExpiry: result.membershipExpiry,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }

  void reset() => state = const ScanIdle();
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(
  ScanNotifier.new,
);
