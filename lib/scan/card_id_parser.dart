import 'dart:convert';

/// The two shapes a Qwallet QR code carries, matching what the web scanner at
/// `/dashboard/scan` already accepts: a JSON object with a `cardId`, or the
/// bare id itself.
///
/// Returns null for anything else, so a customer's boarding pass or a poster's
/// URL does not become a lookup for a card that cannot exist.
String? parseCardId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // JSON first: a payload is authoritative and its casing is the pass's own.
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map && decoded['cardId'] is String) {
      final id = (decoded['cardId'] as String).trim();
      return id.isEmpty ? null : id;
    }
    // Valid JSON without a cardId is not a loyalty card.
    return null;
  } on FormatException {
    // Not JSON. Fall through to the bare-id form.
  }

  // Bare ids are alphanumeric. Upper-cased because that is the form the API
  // and the pass's own altText use.
  if (RegExp(r'^[A-Za-z0-9]{5,20}$').hasMatch(trimmed)) {
    return trimmed.toUpperCase();
  }
  return null;
}
