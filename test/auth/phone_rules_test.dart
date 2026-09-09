import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/auth/country_codes.dart';
import 'package:qwallet_scan/auth/phone_rules.dart';

void main() {
  group('toE164', () {
    test('joins the picked country to the digits typed', () {
      expect(toE164('33123456', '+974'), '+97433123456');
      expect(toE164('3312 3456', '+974'), '+97433123456');
      expect(toE164('3312-3456', '+974'), '+97433123456');
    });

    test('drops a trunk zero for countries with a rule', () {
      expect(toE164('033123456', '+974'), '+97433123456');
    });

    test('leaves a leading zero alone where no rule claims to know', () {
      // Italy's landlines keep theirs as a real digit, and Italy has no rule
      // here — guessing would delete part of a working number.
      expect(toE164('0212345678', '+39'), '+390212345678');
    });

    test('unwinds a country code typed on top of the picked one', () {
      // The picker already supplies +974; someone typing their whole number
      // arrives here doubled.
      expect(toE164('97433123456', '+974'), '+97433123456');
    });

    test(
      'leaves a national number alone that merely opens with those digits',
      () {
        // Unwinding is only attempted when the number is otherwise wrong.
        expect(toE164('97412345', '+974').length, '+97497412345'.length);
      },
    );
  });

  group('phoneProblem', () {
    test('nothing typed is empty, not invalid', () {
      expect(phoneProblem('', '+974'), PhoneProblem.empty);
      expect(phoneProblem('   ', '+974'), PhoneProblem.empty);
    });

    test("Qatar's rule is enforced: eight digits, starting 3 to 7", () {
      expect(phoneProblem('33123456', '+974'), isNull);
      expect(phoneProblem('3312345', '+974'), PhoneProblem.invalid);
      expect(phoneProblem('331234567', '+974'), PhoneProblem.invalid);
      expect(phoneProblem('13123456', '+974'), PhoneProblem.invalid);
    });

    test('India wants ten digits starting 6 to 9', () {
      expect(phoneProblem('9895609703', '+91'), isNull);
      expect(phoneProblem('989560970', '+91'), PhoneProblem.invalid);
      expect(phoneProblem('5895609703', '+91'), PhoneProblem.invalid);
    });

    test('a country with no rule gets E.164 bounds only', () {
      expect(phoneProblem('12345', '+39'), isNull);
      expect(phoneProblem('123', '+39'), PhoneProblem.invalid);
      expect(phoneProblem('1234567890123456', '+39'), PhoneProblem.invalid);
    });
  });

  group('the country list', () {
    test('every dial code the rules name is offered by the picker', () {
      // A rule for a country the picker cannot select is a rule that never
      // runs; a picker entry with no rule is fine, it just falls back to E.164.
      final offered = countryCodes.map((c) => c.dial).toSet();
      for (final dial in phoneRules.keys) {
        expect(
          offered,
          contains(dial),
          reason: '$dial has a rule but no entry',
        );
      }
    });

    test('carries the whole list, not a trimmed one', () {
      expect(countryCodes.length, greaterThan(200));
      expect(countryCodes.firstWhere((c) => c.dial == '+974').name, 'Qatar');
    });
  });
}
