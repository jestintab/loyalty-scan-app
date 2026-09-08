import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/scan/recent_actions.dart';

void main() {
  test('an action just taken is remembered against that card', () {
    final container = ProviderContainer.test();
    final recent = container.read(recentActionsProvider.notifier);

    recent.record('CARD1', CardAction.stamps);

    expect(recent.sinceLast('CARD1', CardAction.stamps), isNotNull);
  });

  test('a different card is not implicated', () {
    final container = ProviderContainer.test();
    final recent = container.read(recentActionsProvider.notifier);

    recent.record('CARD1', CardAction.stamps);

    expect(recent.sinceLast('CARD2', CardAction.stamps), isNull);
  });

  test('a different action on the same card is not implicated', () {
    final container = ProviderContainer.test();
    final recent = container.read(recentActionsProvider.notifier);

    recent.record('CARD1', CardAction.stamps);

    // Stamping then redeeming is an ordinary sequence at a counter; only the
    // same action repeating is suspicious.
    expect(recent.sinceLast('CARD1', CardAction.redeem), isNull);
  });

  test('a record older than the window no longer warns', () {
    final container = ProviderContainer.test();
    final recent = container.read(recentActionsProvider.notifier);

    recent.state = {
      'CARD1|stamps': DateTime.now().subtract(const Duration(minutes: 2)),
    };

    expect(recent.sinceLast('CARD1', CardAction.stamps), isNull);
  });

  test('recording prunes entries that have aged out', () {
    final container = ProviderContainer.test();
    final recent = container.read(recentActionsProvider.notifier);
    recent.state = {
      'OLD|stamps': DateTime.now().subtract(const Duration(minutes: 5)),
    };

    recent.record('CARD1', CardAction.stamps);

    expect(recent.state.keys, ['CARD1|stamps']);
  });

  test('elapsed time is described in words the warning can use', () {
    expect(describeElapsed(const Duration(seconds: 1)), 'a moment ago');
    expect(describeElapsed(const Duration(seconds: 20)), '20 seconds ago');
    expect(describeElapsed(const Duration(seconds: 75)), 'a minute ago');
  });
}
