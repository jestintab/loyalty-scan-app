import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/scan/card_id_parser.dart';

void main() {
  group('parseCardId', () {
    test('reads the JSON payload the wallet passes carry', () {
      expect(
        parseCardId('{"cardId":"ABC1234567","businessId":"biz-1"}'),
        'ABC1234567',
      );
    });

    test('reads a bare card id', () {
      expect(parseCardId('ABC1234567'), 'ABC1234567');
    });

    test('upper-cases a bare id, since the API compares them upper-case', () {
      expect(parseCardId('abc1234567'), 'ABC1234567');
    });

    test('trims surrounding whitespace from a manual entry', () {
      expect(parseCardId('  ABC1234567  '), 'ABC1234567');
    });

    test('does not upper-case an id that came from JSON', () {
      // A JSON payload is the pass's own, exact value — re-casing it would
      // invent an id the server never issued.
      expect(parseCardId('{"cardId":"aBc1234567"}'), 'aBc1234567');
    });

    test('rejects a QR code that is not a loyalty card', () {
      expect(parseCardId('https://example.com'), isNull);
      expect(parseCardId(''), isNull);
      expect(parseCardId('   '), isNull);
      expect(parseCardId('{"notACard":true}'), isNull);
      expect(parseCardId('AB'), isNull); // too short
      expect(parseCardId('A' * 21), isNull); // too long
      expect(parseCardId('ABC-123'), isNull); // punctuation
    });

    test('rejects JSON whose cardId is not a string', () {
      expect(parseCardId('{"cardId":12345}'), isNull);
    });
  });
}
