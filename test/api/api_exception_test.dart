import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_exception.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('401 is unauthorized, with a message about the session', () {
      final e = ApiException.fromResponse(401, '{"error":"Invalid token"}');
      expect(e.kind, ApiErrorKind.unauthorized);
      expect(e.message, 'Your session has expired. Please sign in again.');
    });

    test('403 says which access is missing', () {
      final e = ApiException.fromResponse(403, '{"error":"Access denied"}');
      expect(e.kind, ApiErrorKind.forbidden);
      expect(e.message, "You don't have access to this business.");
    });

    test('404 on a card reads as a missing card', () {
      final e = ApiException.fromResponse(404, '{"error":"Card not found"}');
      expect(e.kind, ApiErrorKind.notFound);
      expect(e.message, 'No card found for this code.');
    });

    test('400 shows the server message, which is already customer-facing', () {
      final e = ApiException.fromResponse(
        400,
        '{"error":"This card is not a points-type card"}',
      );
      expect(e.kind, ApiErrorKind.badRequest);
      expect(e.message, 'This card is not a points-type card');
    });

    test('409 shows the server message too', () {
      final e = ApiException.fromResponse(
        409,
        '{"error":"Membership number \\"A1\\" is already in use by another card"}',
      );
      expect(e.kind, ApiErrorKind.conflict);
      expect(e.message, contains('already in use'));
    });

    test('500 does not leak the server body', () {
      final e = ApiException.fromResponse(500, '{"error":"connect ECONNREFUSED"}');
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, 'Something went wrong at our end. Please try again.');
    });

    test('a 400 with an unreadable body still produces a usable message', () {
      final e = ApiException.fromResponse(400, '<html>502 Bad Gateway</html>');
      expect(e.kind, ApiErrorKind.badRequest);
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('network() needs no response at all', () {
      final e = ApiException.network();
      expect(e.kind, ApiErrorKind.network);
      expect(e.message, "Can't reach the server. Check your connection.");
    });
  });
}
