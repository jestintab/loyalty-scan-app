import 'dart:convert';

enum ApiErrorKind {
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  conflict,
  server,
  network,
}

/// Every failure the app can show a person, with the wording already decided.
///
/// The API's own 400 and 409 messages are written for customers ("This card is
/// not a points-type card"), so those pass through untouched. A 500 body is
/// not — it can carry a stack trace or a connection string — so it is replaced.
class ApiException implements Exception {
  ApiException(this.kind, this.message);

  final ApiErrorKind kind;
  final String message;

  factory ApiException.network() => ApiException(
    ApiErrorKind.network,
    "Can't reach the server. Check your connection.",
  );

  factory ApiException.fromResponse(int statusCode, String body) {
    final serverMessage = _readError(body);

    switch (statusCode) {
      case 401:
        return ApiException(
          ApiErrorKind.unauthorized,
          'Your session has expired. Please sign in again.',
        );
      case 403:
        return ApiException(
          ApiErrorKind.forbidden,
          "You don't have access to this business.",
        );
      case 404:
        return ApiException(
          ApiErrorKind.notFound,
          'No card found for this code.',
        );
      case 400:
        return ApiException(
          ApiErrorKind.badRequest,
          serverMessage ?? 'Something went wrong. Please try again.',
        );
      case 409:
        return ApiException(
          ApiErrorKind.conflict,
          serverMessage ?? 'That conflicts with an existing record.',
        );
      default:
        return ApiException(
          ApiErrorKind.server,
          'Something went wrong at our end. Please try again.',
        );
    }
  }

  /// The API's `{ "error": "..." }` shape. A body that is not JSON, or is JSON
  /// without an `error` string, yields null so the caller substitutes its own
  /// wording — a proxy's HTML error page must never reach a customer's screen.
  static String? _readError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  String toString() => 'ApiException($kind): $message';
}
