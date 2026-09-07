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

  void reset() => state = const ScanIdle();
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(ScanNotifier.new);
