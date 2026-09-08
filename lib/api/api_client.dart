import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_notifier.dart';
import 'api_exception.dart';
import 'models/loyalty_card.dart';
import 'models/scan_log_entry.dart';
import 'models/session.dart';

/// Every call this app makes. An interface rather than a concrete class so
/// tests inject a fake through `apiClientProvider.overrideWithValue(...)`
/// instead of mocking HTTP.
abstract class ApiClient {
  Future<Session> login({required String identifier, required String password});

  Future<String> fetchBusinessName(String businessId);

  Future<LoyaltyCard> fetchCard({
    required String cardId,
    required String businessId,
  });

  Future<CardActionResult> addStamps({
    required String cardId,
    required String businessId,
    required int increment,
  });

  Future<CardActionResult> addToRewards({
    required String cardId,
    required String businessId,
  });

  Future<CardActionResult> redeem({
    required String cardId,
    required String businessId,
  });

  /// [points] is signed: positive adds, negative deducts.
  Future<PointsResult> adjustPoints({
    required String cardId,
    required String businessId,
    required int points,
  });

  Future<MembershipResult> renewMembership({
    required String cardId,
    required String businessId,
    required int expiryMonths,
  });

  Future<ScanLogPage> fetchScanLog({
    required String businessId,
    String? cursor,
    int limit = 20,
  });
}

class HttpApiClient implements ApiClient {
  HttpApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    String? Function()? tokenReader,
  }) : _http = httpClient ?? http.Client(),
       _tokenReader = tokenReader ?? (() => null);

  final String baseUrl;
  final http.Client _http;
  final String? Function() _tokenReader;

  Map<String, String> get _headers {
    final token = _tokenReader();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Path segments are encoded, never interpolated raw: a card id comes off a
  /// QR code a customer's phone displays, which is not somewhere to take a URL
  /// on trust.
  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        ...segments,
      ],
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _http.send(request);
      response = await http.Response.fromStream(streamed);
    } on ApiException {
      rethrow;
    } catch (_) {
      // Any transport-layer failure — DNS, refused connection, timeout — is
      // one thing to the person holding the phone.
      throw ApiException.network();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        ApiErrorKind.server,
        'Something went wrong at our end. Please try again.',
      );
    }
    return decoded;
  }

  @override
  Future<Session> login({
    required String identifier,
    required String password,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'auth', 'login']),
      body: {'identifier': identifier, 'password': password},
    );
    return Session.fromJson(json);
  }

  @override
  Future<String> fetchBusinessName(String businessId) async {
    final json = await _send('GET', _uri(['api', 'business', businessId]));
    return (json['businessName'] as String?) ?? businessId;
  }

  @override
  Future<LoyaltyCard> fetchCard({
    required String cardId,
    required String businessId,
  }) async {
    final json = await _send(
      'GET',
      _uri(['api', 'passes', cardId], {'businessId': businessId}),
    );
    return LoyaltyCard.fromJson(json);
  }

  @override
  Future<CardActionResult> addStamps({
    required String cardId,
    required String businessId,
    required int increment,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', cardId, 'stamp']),
      body: {'businessId': businessId, 'increment': increment},
    );
    return CardActionResult.fromJson(json);
  }

  @override
  Future<CardActionResult> addToRewards({
    required String cardId,
    required String businessId,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', cardId, 'add-reward']),
      body: {'businessId': businessId},
    );
    return CardActionResult.fromJson(json);
  }

  @override
  Future<CardActionResult> redeem({
    required String cardId,
    required String businessId,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', cardId, 'redeem']),
      body: {'businessId': businessId},
    );
    return CardActionResult.fromJson(json);
  }

  @override
  Future<PointsResult> adjustPoints({
    required String cardId,
    required String businessId,
    required int points,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', 'points', cardId]),
      body: {'businessId': businessId, 'points': points},
    );
    return PointsResult.fromJson(json);
  }

  @override
  Future<MembershipResult> renewMembership({
    required String cardId,
    required String businessId,
    required int expiryMonths,
  }) async {
    final json = await _send(
      'POST',
      _uri(['api', 'passes', 'membership', cardId]),
      body: {'businessId': businessId, 'expiryMonths': expiryMonths},
    );
    return MembershipResult.fromJson(json);
  }

  @override
  Future<ScanLogPage> fetchScanLog({
    required String businessId,
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      _uri(
        ['api', 'passes', 'scan-log'],
        {'businessId': businessId, 'limit': '$limit', 'cursor': ?cursor},
      ),
    );
    return ScanLogPage.fromJson(json);
  }
}

// app.qwallet.me, not api.qwallet.me: the API and the dashboard are served
// from the same host — /health there answers with the database status, and
// NEXT_PUBLIC_API_URL in the dashboard points at it too. There is no
// api.qwallet.me; it does not resolve.
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://app.qwallet.me',
);

final apiClientProvider = Provider<ApiClient>((ref) {
  // read, not watch: rebuilding the client on every auth change would drop
  // in-flight requests. The reader closes over the notifier, so the token it
  // returns is always current.
  return HttpApiClient(
    baseUrl: _baseUrl,
    tokenReader: () => ref.read(authProvider.notifier).token,
  );
});
