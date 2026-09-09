/// Phone number checking for the sign-in form.
///
/// A port of loyalty-dashboard/src/lib/phone.ts, which is itself the mirror of
/// loyalty-pass-api/src/services/phoneNumber.js — and that one is the
/// authority, since it re-checks every number. A check here is a courtesy, not
/// a guarantee. Keep the three rule tables in step: a country strict in one and
/// loose in another is accepted on one screen and refused on the next.
///
/// Simpler than the API's copy in one way. There the country code has to be
/// found inside the string; here it is whatever the picker has selected, so
/// this only validates the national part beside it.
library;

class PhoneRule {
  const PhoneRule({required this.lengths, this.startsWith});

  /// Permitted national-number digit counts.
  final List<int> lengths;

  /// Permitted leading digits, or null for any.
  final List<String>? startsWith;
}

/// Only countries worth being strict about: the GCC, where this is sold, and
/// where most of Qatar's residents come from. Everything else gets E.164's own
/// bounds, because a wrong guess at a numbering plan turns a real member of
/// staff away from their own till.
const phoneRules = <String, PhoneRule>{
  '+974': PhoneRule(
    lengths: [8],
    startsWith: ['3', '4', '5', '6', '7'],
  ), // Qatar
  '+971': PhoneRule(lengths: [8, 9]), // UAE
  '+966': PhoneRule(lengths: [9]), // Saudi Arabia
  '+965': PhoneRule(lengths: [8]), // Kuwait
  '+973': PhoneRule(lengths: [8]), // Bahrain
  '+968': PhoneRule(lengths: [8]), // Oman
  '+91': PhoneRule(lengths: [10], startsWith: ['6', '7', '8', '9']), // India
  '+92': PhoneRule(lengths: [10], startsWith: ['3']), // Pakistan
  '+63': PhoneRule(lengths: [10], startsWith: ['9']), // Philippines
};

const _minNationalDigits = 4;
const _maxE164Digits = 15;

/// Why a number is unusable, or null when it is fine.
enum PhoneProblem { empty, invalid }

/// The national part as it should be sent: digits only, with the habits people
/// type stripped — spacing, a trunk zero, and the country code typed again on
/// top of the one the picker already supplies.
///
/// The trunk zero comes off only for countries with a rule, since a few
/// numbering plans (Italy's landlines, for one) keep a leading zero as a real
/// digit, and those are not ones this file claims to know.
String normalizeNationalNumber(String raw, String dial) {
  final rule = phoneRules[dial];
  final dialDigits = dial.replaceAll(RegExp(r'\D'), '');
  var digits = raw.replaceAll(RegExp(r'\D'), '');

  if (rule != null) digits = digits.replaceFirst(RegExp(r'^0+'), '');

  // Unwound only when the number is otherwise wrong, so a national number that
  // legitimately opens with those digits is left alone.
  if (!_nationalIsValid(digits, dial) && digits.startsWith(dialDigits)) {
    final rest = digits.substring(dialDigits.length);
    final unwound = rule != null ? rest.replaceFirst(RegExp(r'^0+'), '') : rest;
    if (_nationalIsValid(unwound, dial)) return unwound;
  }

  return digits;
}

bool _nationalIsValid(String national, String dial) {
  final rule = phoneRules[dial];
  final dialDigits = dial.replaceAll(RegExp(r'\D'), '');
  if (dialDigits.length + national.length > _maxE164Digits) return false;
  if (rule == null) return national.length >= _minNationalDigits;
  if (!rule.lengths.contains(national.length)) return false;
  final leading = rule.startsWith;
  if (leading != null && (national.isEmpty || !leading.contains(national[0]))) {
    return false;
  }
  return true;
}

/// Why this number cannot be used, or null when it can.
PhoneProblem? phoneProblem(String raw, String dial) {
  final national = normalizeNationalNumber(raw, dial);
  if (national.isEmpty) return PhoneProblem.empty;
  return _nationalIsValid(national, dial) ? null : PhoneProblem.invalid;
}

/// The full number to sign in with, e.g. "+97433123456".
String toE164(String raw, String dial) =>
    '$dial${normalizeNationalNumber(raw, dial)}';
