import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What to tell someone about the action that just finished, left for the
/// screen they land on.
///
/// A SnackBar belongs to whichever Scaffold is registered when it goes up, and
/// the screen raising one here is on its way out — raised from the card screen
/// it leaves with the card screen, and raising it a frame later races the
/// route transition. So the message is handed over instead, and the dashboard
/// shows it from its own Scaffold once it is on screen.
final actionMessageProvider = NotifierProvider<ActionMessage, String?>(
  ActionMessage.new,
);

class ActionMessage extends Notifier<String?> {
  @override
  String? build() => null;

  void post(String message) => state = message;

  /// Returns the pending message and clears it, so it is shown once.
  String? take() {
    final message = state;
    if (message != null) state = null;
    return message;
  }
}
