# Qwallet Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter app for counter staff with three screens — sign in, scan a
loyalty card and act on it, and read the shop's scan log.

**Architecture:** A thin client over an API that already exists and needs no
changes. One `ApiClient` interface owns every HTTP call and the mapping from
status codes to a single `ApiException`; Riverpod notifiers hold screen state
and are tested against a fake `ApiClient` with no widget tree; `go_router`
redirects on auth state so no screen has to check whether it should be visible.

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 via fvm, `flutter_riverpod` ^3.4.3,
`go_router` ^18.0.1, `mobile_scanner` ^7.4.0, `flutter_secure_storage` ^11.0.0,
`http` ^1.6.0.

**Spec:** `docs/superpowers/specs/2026-09-07-qwallet-scan-app-design.md`

## Global Constraints

- **Every command runs through fvm.** `fvm flutter test`, `fvm flutter analyze`,
  `fvm dart format .`. A bare `flutter` is not on PATH and will pick up a
  different SDK if it ever is.
- **Riverpod 3, not 2.** `Ref` has no type parameter — write `Ref`, never
  `Ref<T>`. `AutoDisposeNotifier` and `AutoDisposeRef` do not exist; providers
  are kept alive by default and opt into disposal with
  `NotifierProvider.autoDispose`. Tests build containers with
  `ProviderContainer.test()`, which disposes itself via `addTearDown`.
- **No API changes.** Every endpoint used here exists today. If a task seems to
  need a new field, it is the task that is wrong.
- **Never trust a locally computed count after an action.** Every action
  response carries the new state; render that, never `count + 1`.
- **`businessId` is required on every call.** There is no implicit "current
  business" on the server.
- **Base URL** comes from `--dart-define=API_BASE_URL=…`, defaulting to
  `https://api.qwallet.me`. Never hardcode it in a widget.
- **No `print`.** `analysis_options.yaml` enables `avoid_print`; the analyzer
  must stay clean.

---

## File Structure

```
lib/
  main.dart                       ProviderScope + runApp
  app.dart                        MaterialApp.router, theme
  router.dart                     routes + the auth redirect
  api/
    api_exception.dart            ApiException + ApiErrorKind
    api_client.dart               ApiClient interface, HttpApiClient, provider
    models/
      session.dart                Session
      loyalty_card.dart           LoyaltyCard, CardActionResult
      scan_log_entry.dart         ScanLogEntry, ScanLogPage
  auth/
    token_store.dart              TokenStore over flutter_secure_storage
    auth_notifier.dart            AuthState, AuthNotifier, authProvider
    login_screen.dart
    business_picker_screen.dart
  scan/
    card_id_parser.dart           parseCardId
    scan_notifier.dart            ScanState, ScanNotifier, scanProvider
    scan_screen.dart              camera + manual entry
    card_result_view.dart         dispatch on templateType
    reward_actions.dart
    points_actions.dart
    membership_actions.dart
  logs/
    logs_notifier.dart            LogsState, LogsNotifier, logsProvider
    logs_screen.dart
  ui/
    async_button.dart             button that shows its own in-flight state
    message_view.dart             centred icon + message + optional retry
test/
  api/api_exception_test.dart
  api/http_api_client_test.dart
  api/models_test.dart
  auth/auth_notifier_test.dart
  scan/card_id_parser_test.dart
  scan/scan_notifier_test.dart
  logs/logs_notifier_test.dart
  widget/login_screen_test.dart
  widget/reward_actions_test.dart
  widget/points_membership_test.dart
  widget/logs_screen_test.dart
  support/fake_api_client.dart    shared fake, implements ApiClient
```

---

### Task 1: Project scaffold and toolchain

**Files:**
- Create: `.fvmrc`, `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`
- Test: `test/smoke_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: a project where `fvm flutter test` and `fvm flutter analyze` run
  clean, with every dependency of this plan resolved.

- [ ] **Step 1: Pin the SDK and create the project**

Run from `~/Desktop/Learn/Loyalty/loyalty-scan-app` (the repo already exists and
holds `docs/` and `.gitignore` — `flutter create` fills in around them):

```bash
fvm use 3.44.8 --force --skip-pub-get --skip-setup
fvm flutter create --org me.qwallet --project-name qwallet_scan --platforms=android,ios .
```

`--force` is not optional here. `fvm use` validates that it is being run inside
a Flutter project, and in an empty directory it stops on an interactive prompt
that a non-interactive shell will hang on forever. `--skip-pub-get` for the same
reason: there is no pubspec to resolve until the next line creates one.

- [ ] **Step 2: Add the dependencies**

```bash
fvm flutter pub add flutter_riverpod:^3.4.3 go_router:^18.0.1 \
  mobile_scanner:^7.4.0 flutter_secure_storage:^11.0.0 http:^1.6.0
```

- [ ] **Step 3: Turn on the lints this plan assumes**

Replace `analysis_options.yaml` with:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    avoid_print: true
    prefer_single_quotes: true
    require_trailing_commas: true
```

- [ ] **Step 4: Write the smoke test**

`test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the toolchain runs tests', () {
    expect(2 + 2, 4);
  });
}
```

- [ ] **Step 5: Delete the counter-app test that will not compile**

`flutter create` writes `test/widget_test.dart` against the demo `MyApp`, which
later tasks replace. Remove it now rather than letting it break Task 2's run:

```bash
rm -f test/widget_test.dart
```

- [ ] **Step 6: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: 1 test passes; analyze reports no issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold the Flutter project on the pinned SDK"
```

---

### Task 2: API errors and the client interface

**Files:**
- Create: `lib/api/api_exception.dart`, `lib/api/api_client.dart`
- Test: `test/api/api_exception_test.dart`, `test/api/http_api_client_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ApiErrorKind { unauthorized, forbidden, notFound, badRequest, conflict, server, network }`
  - `class ApiException implements Exception { ApiErrorKind kind; String message; }`
  - `ApiException.fromResponse(int statusCode, String body)`
  - `abstract class ApiClient` with the methods listed in Step 5.
  - `class HttpApiClient implements ApiClient`, constructor
    `HttpApiClient({required String baseUrl, http.Client? httpClient, String? Function()? tokenReader})`
  - `final apiClientProvider = Provider<ApiClient>(...)`

- [ ] **Step 1: Write the failing error-mapping tests**

`test/api/api_exception_test.dart`:

```dart
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
```

- [ ] **Step 2: Run it to watch it fail**

Run: `fvm flutter test test/api/api_exception_test.dart`
Expected: FAIL — `api_exception.dart` does not exist.

- [ ] **Step 3: Implement the exception**

`lib/api/api_exception.dart`:

```dart
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
        return ApiException(ApiErrorKind.notFound, 'No card found for this code.');
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
```

- [ ] **Step 4: Verify the mapping passes**

Run: `fvm flutter test test/api/api_exception_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Write the failing client tests**

`test/api/http_api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';

/// Records what the client sent, and replies with whatever the test says.
MockClient respondWith(
  int status,
  String body, {
  List<http.Request>? capture,
}) {
  return MockClient((request) async {
    capture?.add(request);
    return http.Response(body, status, headers: {'content-type': 'application/json'});
  });
}

void main() {
  group('HttpApiClient', () {
    test('login posts the identifier and password, and returns the session', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(
          200,
          jsonEncode({
            'token': 'jwt-abc',
            'user': {
              'id': 7,
              'email': 'sam@shop.qa',
              'name': 'Sam',
              'role': 'staff',
              'businessIds': ['biz-1'],
            },
          }),
          capture: sent,
        ),
      );

      final session = await client.login(identifier: 'sam@shop.qa', password: 'pw');

      expect(sent.single.url.toString(), 'https://api.test/api/auth/login');
      expect(jsonDecode(sent.single.body), {
        'identifier': 'sam@shop.qa',
        'password': 'pw',
      });
      expect(session.token, 'jwt-abc');
      expect(session.businessIds, ['biz-1']);
    });

    test('an authenticated call sends the bearer token from the reader', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(200, _cardJson, capture: sent),
        tokenReader: () => 'jwt-abc',
      );

      await client.fetchCard(cardId: 'ABC123', businessId: 'biz-1');

      expect(sent.single.headers['Authorization'], 'Bearer jwt-abc');
      expect(
        sent.single.url.toString(),
        'https://api.test/api/passes/ABC123?businessId=biz-1',
      );
    });

    test('a card id with a slash in it cannot escape its path segment', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(200, _cardJson, capture: sent),
      );

      await client.fetchCard(cardId: 'a/../b', businessId: 'biz-1');

      expect(sent.single.url.path, '/api/passes/a%2F..%2Fb');
    });

    test('a non-2xx becomes an ApiException of the right kind', () async {
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(404, '{"error":"Card not found"}'),
      );

      expect(
        () => client.fetchCard(cardId: 'NOPE', businessId: 'biz-1'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.notFound)),
      );
    });

    test('a socket failure becomes a network ApiException, not a raw error', () async {
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(
        () => client.fetchCard(cardId: 'ABC123', businessId: 'biz-1'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network)),
      );
    });

    test('addStamps posts the increment and returns the new state', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(
          200,
          jsonEncode({
            'cardId': 'ABC123',
            'stampCount': 5,
            'stampsRequired': 10,
            'rewardsAvailable': 0,
          }),
          capture: sent,
        ),
      );

      final result = await client.addStamps(
        cardId: 'ABC123',
        businessId: 'biz-1',
        increment: 2,
      );

      expect(jsonDecode(sent.single.body), {'businessId': 'biz-1', 'increment': 2});
      expect(result.stampCount, 5);
      expect(result.rewardsAvailable, 0);
    });
  });
}

/// http's MockClient rethrows whatever the handler throws; this stands in for a
/// dropped connection without needing dart:io in a test that also runs on web.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

const _cardJson = '''
{"cardId":"ABC123","businessId":"biz-1","userName":"Ali","userEmail":"a@b.qa",
 "userPhone":null,"templateType":"reward","stampCount":3,"rewardsAvailable":0,
 "pointsBalance":0,"pointsExpiry":null,"membershipNumber":null,
 "membershipCategory":null,"membershipExpiry":null,
 "merchantData":{"businessName":"Wake","rewardDescription":"A free flat white",
 "stampsRequired":10}}
''';
```

- [ ] **Step 6: Run them to watch them fail**

Run: `fvm flutter test test/api/http_api_client_test.dart`
Expected: FAIL — `api_client.dart` does not exist.

- [ ] **Step 7: Implement the client**

`lib/api/api_client.dart`. `Session`, `LoyaltyCard`, `CardActionResult`,
`ScanLogPage` and `Business` arrive in Task 3 — write this file now and let the
model imports fail; Step 8 of Task 3 is where both compile together. To keep
this task's tests runnable, create the five model files as part of Step 7 with
only the constructor and `fromJson` shapes Task 3 specifies, then let Task 3
add their tests and any remaining fields.

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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

  Future<LoyaltyCard> fetchCard({required String cardId, required String businessId});

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
  })  : _http = httpClient ?? http.Client(),
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
      pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), ...segments],
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
  Future<Session> login({required String identifier, required String password}) async {
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
      _uri(['api', 'passes', 'scan-log'], {
        'businessId': businessId,
        'limit': '$limit',
        // Dart 3's null-aware element: the entry is omitted when cursor is
        // null. `if (cursor != null)` here trips use_null_aware_elements.
        'cursor': ?cursor,
      }),
    );
    return ScanLogPage.fromJson(json);
  }
}

/// Overridden in tests. Wired to a real client with a live token reader in
/// Task 4, once the token store exists.
final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError('apiClientProvider is wired in Task 4');
});
```

- [ ] **Step 8: Verify**

Run: `fvm flutter test test/api/ && fvm flutter analyze`
Expected: both client and exception suites pass; analyze clean.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add the API client and one exception type for every failure"
```

---

### Task 3: Models

**Files:**
- Create: `lib/api/models/session.dart`, `lib/api/models/loyalty_card.dart`,
  `lib/api/models/scan_log_entry.dart`
- Test: `test/api/models_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Session({required String token, required int userId, required String name, required String role, required List<String> businessIds})`, `Session.fromJson`
  - `LoyaltyCard` with `cardId, businessId, userName, userEmail, userPhone, templateType, stampCount, rewardsAvailable, stampsRequired, rewardDescription, businessName, pointsBalance, pointsExpiry, membershipNumber, membershipCategory, membershipExpiry`, `LoyaltyCard.fromJson`
  - `CardActionResult({required int stampCount, required int stampsRequired, required int rewardsAvailable})`, `.fromJson`
  - `PointsResult({required int pointsBalance, DateTime? pointsExpiry})`, `.fromJson`
  - `MembershipResult({String? membershipNumber, String? membershipCategory, DateTime? membershipExpiry})`, `.fromJson`
  - `ScanLogEntry({required int id, required ScanLogType type, required String cardId, String? staffName, String? customerName, required int stampsAdded, required int stampsBefore, required int stampsAfter, required DateTime loggedAt})`, `.fromJson`
  - `enum ScanLogType { stamp, redemption }`
  - `ScanLogPage({required List<ScanLogEntry> entries, required bool hasMore, String? nextCursor})`, `.fromJson`

- [ ] **Step 1: Write the failing tests**

`test/api/models_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/api/models/session.dart';

void main() {
  group('Session', () {
    test('reads the token and the businesses the user is linked to', () {
      final session = Session.fromJson(jsonDecode('''
        {"token":"jwt","user":{"id":7,"email":"s@x.qa","name":"Sam",
         "role":"staff","businessIds":["biz-1","biz-2"]}}
      '''));

      expect(session.token, 'jwt');
      expect(session.userId, 7);
      expect(session.name, 'Sam');
      expect(session.role, 'staff');
      expect(session.businessIds, ['biz-1', 'biz-2']);
    });

    test('a user linked to nothing yields an empty list, not a crash', () {
      final session = Session.fromJson(jsonDecode('''
        {"token":"jwt","user":{"id":7,"email":"s@x.qa","name":"Sam",
         "role":"business","businessIds":[]}}
      '''));

      expect(session.businessIds, isEmpty);
    });
  });

  group('LoyaltyCard', () {
    test('reads a reward card, flattening the merchantData it needs', () {
      final card = LoyaltyCard.fromJson(jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":"Ali",
         "userEmail":"a@b.qa","userPhone":"+97433123456","templateType":"reward",
         "stampCount":7,"rewardsAvailable":1,"pointsBalance":0,
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,
         "merchantData":{"businessName":"Wake Qatar",
          "rewardDescription":"A free flat white","stampsRequired":10}}
      '''));

      expect(card.cardId, 'ABC123');
      expect(card.templateType, 'reward');
      expect(card.stampCount, 7);
      expect(card.stampsRequired, 10);
      expect(card.rewardsAvailable, 1);
      expect(card.rewardDescription, 'A free flat white');
      expect(card.businessName, 'Wake Qatar');
    });

    test('parses the nulls the API really sends on a reward card', () {
      // pointsExpiry, membershipExpiry and userPhone are all null on a reward
      // card — the API returns every field for every type.
      final card = LoyaltyCard.fromJson(jsonDecode('''
        {"cardId":"ABC123","businessId":"biz-1","userName":"Ali",
         "userEmail":"a@b.qa","userPhone":null,"templateType":"reward",
         "stampCount":0,"rewardsAvailable":0,"pointsBalance":0,
         "pointsExpiry":null,"membershipNumber":null,"membershipCategory":null,
         "membershipExpiry":null,"merchantData":{}}
      '''));

      expect(card.userPhone, isNull);
      expect(card.pointsExpiry, isNull);
      expect(card.membershipExpiry, isNull);
      expect(card.stampsRequired, 0);
      expect(card.rewardDescription, '');
      expect(card.businessName, isNull);
    });

    test('reads a membership card, including its dates', () {
      final card = LoyaltyCard.fromJson(jsonDecode('''
        {"cardId":"M1","businessId":"biz-1","userName":"Ali","userEmail":null,
         "userPhone":null,"templateType":"membership","stampCount":0,
         "rewardsAvailable":0,"pointsBalance":0,"pointsExpiry":null,
         "membershipNumber":"MBR-0007","membershipCategory":"Gold",
         "membershipExpiry":"2027-01-31T00:00:00.000Z","merchantData":{}}
      '''));

      expect(card.membershipNumber, 'MBR-0007');
      expect(card.membershipCategory, 'Gold');
      expect(card.membershipExpiry, DateTime.utc(2027, 1, 31));
    });
  });

  group('ScanLogPage', () {
    test('reads both row types out of the union the API returns', () {
      final page = ScanLogPage.fromJson(jsonDecode('''
        {"scanLog":[
          {"id":2,"type":"redemption","cardId":"ABC123","staffName":"Sam",
           "customerName":"Ali","customerEmail":"a@b.qa","stampsAdded":10,
           "stampsBefore":10,"stampsAfter":0,
           "loggedAt":"2026-09-07T09:15:00.000Z"},
          {"id":1,"type":"stamp","cardId":"ABC123","staffName":null,
           "customerName":"Ali","customerEmail":"a@b.qa","stampsAdded":1,
           "stampsBefore":6,"stampsAfter":7,
           "loggedAt":"2026-09-07T08:00:00.000Z"}],
         "hasMore":true,"nextCursor":"2026-09-07T08:00:00.000Z"}
      '''));

      expect(page.entries, hasLength(2));
      expect(page.entries.first.type, ScanLogType.redemption);
      expect(page.entries.last.type, ScanLogType.stamp);
      expect(page.entries.last.staffName, isNull);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2026-09-07T08:00:00.000Z');
    });

    test('the last page has no cursor', () {
      final page = ScanLogPage.fromJson(
        jsonDecode('{"scanLog":[],"hasMore":false,"nextCursor":null}'),
      );

      expect(page.entries, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `fvm flutter test test/api/models_test.dart`
Expected: FAIL — the models created in Task 2 Step 7 do not yet parse these
shapes (or do not exist).

- [ ] **Step 3: Write `session.dart`**

```dart
/// A signed-in user plus the token that authenticates them.
class Session {
  const Session({
    required this.token,
    required this.userId,
    required this.email,
    required this.name,
    required this.role,
    required this.businessIds,
  });

  final String token;
  final int userId;
  final String? email;
  final String name;

  /// 'admin', 'business', 'staff' or 'customer'. The last cannot use this app —
  /// AuthNotifier refuses it before the token is stored.
  final String role;

  /// Every business this user may act on. Empty is a real state: an owner can
  /// unlink a staff member from their last shop.
  final List<String> businessIds;

  factory Session.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    return Session(
      token: json['token'] as String,
      userId: user['id'] as int,
      email: user['email'] as String?,
      name: (user['name'] as String?) ?? '',
      role: user['role'] as String,
      businessIds:
          ((user['businessIds'] as List?) ?? const []).map((e) => e as String).toList(),
    );
  }
}
```

- [ ] **Step 4: Write `loyalty_card.dart`**

```dart
/// Reads only the fields the counter needs. The API returns colours, image
/// URLs and custom field definitions too — this app renders none of them.
class LoyaltyCard {
  const LoyaltyCard({
    required this.cardId,
    required this.businessId,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
    required this.templateType,
    required this.stampCount,
    required this.rewardsAvailable,
    required this.stampsRequired,
    required this.rewardDescription,
    required this.businessName,
    required this.pointsBalance,
    required this.pointsExpiry,
    required this.membershipNumber,
    required this.membershipCategory,
    required this.membershipExpiry,
  });

  final String cardId;
  final String businessId;
  final String? userName;
  final String? userEmail;
  final String? userPhone;

  /// 'reward', 'points' or 'membership'. Anything else is shown as unsupported
  /// rather than guessed at.
  final String templateType;

  final int stampCount;
  final int rewardsAvailable;

  /// The ladder total on a multi-milestone card, not the current rung. Shown,
  /// never used to decide whether an action is allowed — see the spec.
  final int stampsRequired;

  final String rewardDescription;
  final String? businessName;
  final int pointsBalance;
  final DateTime? pointsExpiry;
  final String? membershipNumber;
  final String? membershipCategory;
  final DateTime? membershipExpiry;

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    final merchant =
        ((json['merchantData'] as Map?) ?? const {}).cast<String, dynamic>();
    return LoyaltyCard(
      cardId: json['cardId'] as String,
      businessId: json['businessId'] as String,
      userName: json['userName'] as String?,
      userEmail: json['userEmail'] as String?,
      userPhone: json['userPhone'] as String?,
      templateType: (json['templateType'] as String?) ?? 'reward',
      stampCount: _int(json['stampCount']),
      rewardsAvailable: _int(json['rewardsAvailable']),
      stampsRequired: _int(merchant['stampsRequired']),
      rewardDescription: (merchant['rewardDescription'] as String?) ?? '',
      businessName: merchant['businessName'] as String?,
      pointsBalance: _int(json['pointsBalance']),
      pointsExpiry: _date(json['pointsExpiry']),
      membershipNumber: json['membershipNumber'] as String?,
      membershipCategory: json['membershipCategory'] as String?,
      membershipExpiry: _date(json['membershipExpiry']),
    );
  }
}

/// What every reward action returns. The screen renders these numbers rather
/// than incrementing its own — the server owns the count.
class CardActionResult {
  const CardActionResult({
    required this.stampCount,
    required this.stampsRequired,
    required this.rewardsAvailable,
  });

  final int stampCount;
  final int stampsRequired;
  final int rewardsAvailable;

  factory CardActionResult.fromJson(Map<String, dynamic> json) => CardActionResult(
        stampCount: _int(json['stampCount']),
        stampsRequired: _int(json['stampsRequired']),
        rewardsAvailable: _int(json['rewardsAvailable']),
      );
}

class PointsResult {
  const PointsResult({required this.pointsBalance, required this.pointsExpiry});

  final int pointsBalance;
  final DateTime? pointsExpiry;

  factory PointsResult.fromJson(Map<String, dynamic> json) => PointsResult(
        pointsBalance: _int(json['pointsBalance']),
        pointsExpiry: _date(json['pointsExpiry']),
      );
}

class MembershipResult {
  const MembershipResult({
    required this.membershipNumber,
    required this.membershipCategory,
    required this.membershipExpiry,
  });

  final String? membershipNumber;
  final String? membershipCategory;
  final DateTime? membershipExpiry;

  factory MembershipResult.fromJson(Map<String, dynamic> json) => MembershipResult(
        membershipNumber: json['membershipNumber'] as String?,
        membershipCategory: json['membershipCategory'] as String?,
        membershipExpiry: _date(json['membershipExpiry']),
      );
}

/// Postgres BIGINT and NUMERIC reach JSON as strings through node-postgres, and
/// a missing key reaches here as null. All three mean zero to a counter.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
```

- [ ] **Step 5: Write `scan_log_entry.dart`**

```dart
enum ScanLogType { stamp, redemption }

/// One row of the union of scan_log and redemption_log the API returns.
class ScanLogEntry {
  const ScanLogEntry({
    required this.id,
    required this.type,
    required this.cardId,
    required this.staffName,
    required this.customerName,
    required this.stampsAdded,
    required this.stampsBefore,
    required this.stampsAfter,
    required this.loggedAt,
  });

  final int id;
  final ScanLogType type;
  final String cardId;
  final String? staffName;
  final String? customerName;
  final int stampsAdded;
  final int stampsBefore;
  final int stampsAfter;
  final DateTime loggedAt;

  factory ScanLogEntry.fromJson(Map<String, dynamic> json) => ScanLogEntry(
        id: _int(json['id']),
        type: json['type'] == 'redemption' ? ScanLogType.redemption : ScanLogType.stamp,
        cardId: (json['cardId'] as String?) ?? '',
        staffName: json['staffName'] as String?,
        customerName: json['customerName'] as String?,
        stampsAdded: _int(json['stampsAdded']),
        stampsBefore: _int(json['stampsBefore']),
        stampsAfter: _int(json['stampsAfter']),
        loggedAt: DateTime.tryParse(json['loggedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class ScanLogPage {
  const ScanLogPage({
    required this.entries,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<ScanLogEntry> entries;
  final bool hasMore;

  /// The last row's `loggedAt`. Pass it back as `cursor` for the next page.
  final String? nextCursor;

  factory ScanLogPage.fromJson(Map<String, dynamic> json) => ScanLogPage(
        entries: ((json['scanLog'] as List?) ?? const [])
            .map((e) => ScanLogEntry.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        hasMore: json['hasMore'] == true,
        nextCursor: json['nextCursor'] as String?,
      );
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
```

- [ ] **Step 6: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: model, client and exception suites all pass; analyze clean.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Parse the API's payloads, nulls and all"
```

---

### Task 4: Token storage and auth state

**Files:**
- Create: `lib/auth/token_store.dart`, `lib/auth/auth_notifier.dart`,
  `test/support/fake_api_client.dart`
- Modify: `lib/api/api_client.dart` (wire `apiClientProvider` for real)
- Test: `test/auth/auth_notifier_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Session`, `ApiException` from Tasks 2-3.
- Produces:
  - `abstract class TokenStore { Future<StoredAuth?> read(); Future<void> write(StoredAuth); Future<void> clear(); }`
  - `class StoredAuth { String token; String name; String role; List<String> businessIds; String? businessId; }`
  - `class SecureTokenStore implements TokenStore`
  - `sealed class AuthState` with `AuthLoading`, `AuthSignedOut({String? error})`, `AuthNeedsBusiness(StoredAuth)`, `AuthSignedIn(StoredAuth)` (its `businessId` is non-null)
  - `class AuthNotifier extends Notifier<AuthState>` with
    `Future<void> restore()`, `Future<void> signIn(String identifier, String password)`,
    `Future<void> chooseBusiness(String businessId)`, `Future<void> signOut({String? reason})`
  - `final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new)`
  - `final tokenStoreProvider = Provider<TokenStore>(...)`
  - `class FakeApiClient implements ApiClient` in `test/support/`

- [ ] **Step 1: Write the shared fake**

`test/support/fake_api_client.dart`:

```dart
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/api/models/session.dart';

/// Every method answers from a field the test sets, and records that it was
/// called. Deliberately not a mock: the assertions in these tests are about
/// what the app did with a response, not about which methods ran.
class FakeApiClient implements ApiClient {
  Session? loginResult;
  ApiException? loginError;
  final List<({String identifier, String password})> loginCalls = [];

  LoyaltyCard? card;
  ApiException? cardError;
  final List<String> fetchedCardIds = [];

  CardActionResult? actionResult;
  ApiException? actionError;
  final List<String> actions = [];

  PointsResult? pointsResult;
  MembershipResult? membershipResult;

  final List<ScanLogPage> logPages = [];
  ApiException? logError;
  final List<String?> logCursors = [];

  String businessName = 'Test Shop';

  /// Completes when the test says so, for asserting on in-flight behaviour.
  /// Left null, calls return immediately.
  Future<void>? gate;

  Future<void> _wait() async {
    if (gate != null) await gate;
  }

  @override
  Future<Session> login({required String identifier, required String password}) async {
    loginCalls.add((identifier: identifier, password: password));
    await _wait();
    if (loginError != null) throw loginError!;
    return loginResult!;
  }

  @override
  Future<String> fetchBusinessName(String businessId) async => businessName;

  @override
  Future<LoyaltyCard> fetchCard({
    required String cardId,
    required String businessId,
  }) async {
    fetchedCardIds.add(cardId);
    await _wait();
    if (cardError != null) throw cardError!;
    return card!;
  }

  @override
  Future<CardActionResult> addStamps({
    required String cardId,
    required String businessId,
    required int increment,
  }) async {
    actions.add('addStamps:$increment');
    await _wait();
    if (actionError != null) throw actionError!;
    return actionResult!;
  }

  @override
  Future<CardActionResult> addToRewards({
    required String cardId,
    required String businessId,
  }) async {
    actions.add('addToRewards');
    await _wait();
    if (actionError != null) throw actionError!;
    return actionResult!;
  }

  @override
  Future<CardActionResult> redeem({
    required String cardId,
    required String businessId,
  }) async {
    actions.add('redeem');
    await _wait();
    if (actionError != null) throw actionError!;
    return actionResult!;
  }

  @override
  Future<PointsResult> adjustPoints({
    required String cardId,
    required String businessId,
    required int points,
  }) async {
    actions.add('adjustPoints:$points');
    await _wait();
    if (actionError != null) throw actionError!;
    return pointsResult!;
  }

  @override
  Future<MembershipResult> renewMembership({
    required String cardId,
    required String businessId,
    required int expiryMonths,
  }) async {
    actions.add('renewMembership:$expiryMonths');
    await _wait();
    if (actionError != null) throw actionError!;
    return membershipResult!;
  }

  @override
  Future<ScanLogPage> fetchScanLog({
    required String businessId,
    String? cursor,
    int limit = 20,
  }) async {
    logCursors.add(cursor);
    await _wait();
    if (logError != null) throw logError!;
    return logPages.removeAt(0);
  }
}

/// An in-memory TokenStore for the same reason.
class FakeTokenStore implements TokenStore {
  StoredAuth? stored;
  int clearCount = 0;

  @override
  Future<StoredAuth?> read() async => stored;

  @override
  Future<void> write(StoredAuth auth) async => stored = auth;

  @override
  Future<void> clear() async {
    stored = null;
    clearCount++;
  }
}
```

Add the import `import 'package:qwallet_scan/auth/token_store.dart';` to that
file once Step 4 creates it.

- [ ] **Step 2: Write the failing auth tests**

`test/auth/auth_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/session.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/token_store.dart';

import '../support/fake_api_client.dart';

Session sessionWith({
  String role = 'staff',
  List<String> businessIds = const ['biz-1'],
}) =>
    Session(
      token: 'jwt',
      userId: 7,
      email: 's@x.qa',
      name: 'Sam',
      role: role,
      businessIds: businessIds,
    );

void main() {
  late FakeApiClient api;
  late FakeTokenStore store;

  ProviderContainer containerWith() {
    api = FakeApiClient();
    store = FakeTokenStore();
    return ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
  }

  test('a staff member with one business lands signed in on that business', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: ['biz-1']);

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    final state = container.read(authProvider);
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).auth.businessId, 'biz-1');
    expect(store.stored!.token, 'jwt');
  });

  test('two businesses stop at the picker rather than guessing', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: ['biz-1', 'biz-2']);

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    expect(container.read(authProvider), isA<AuthNeedsBusiness>());
  });

  test('choosing a business completes the sign-in and persists it', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: ['biz-1', 'biz-2']);
    await container.read(authProvider.notifier).signIn('sam', 'pw');

    await container.read(authProvider.notifier).chooseBusiness('biz-2');

    expect((container.read(authProvider) as AuthSignedIn).auth.businessId, 'biz-2');
    expect(store.stored!.businessId, 'biz-2');
  });

  test('a customer account is refused and nothing is stored', () async {
    final container = containerWith();
    api.loginResult = sessionWith(role: 'customer');

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    final state = container.read(authProvider);
    expect(state, isA<AuthSignedOut>());
    expect((state as AuthSignedOut).error, 'This app is for staff and business owners.');
    expect(store.stored, isNull);
  });

  test('an account linked to no business says so, and stores nothing', () async {
    final container = containerWith();
    api.loginResult = sessionWith(businessIds: const []);

    await container.read(authProvider.notifier).signIn('sam', 'pw');

    final state = container.read(authProvider);
    expect(state, isA<AuthSignedOut>());
    expect(
      (state as AuthSignedOut).error,
      'This account is not linked to a business. Ask the owner to add you.',
    );
    expect(store.stored, isNull);
  });

  test('bad credentials surface the API message', () async {
    final container = containerWith();
    api.loginError = ApiException(ApiErrorKind.unauthorized, 'Invalid credentials');

    await container.read(authProvider.notifier).signIn('sam', 'wrong');

    expect((container.read(authProvider) as AuthSignedOut).error, 'Invalid credentials');
  });

  test('restore brings back a completed session', () async {
    final container = containerWith();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );

    await container.read(authProvider.notifier).restore();

    expect(container.read(authProvider), isA<AuthSignedIn>());
  });

  test('restore with no stored business returns to the picker', () async {
    final container = containerWith();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1', 'biz-2'],
      businessId: null,
    );

    await container.read(authProvider.notifier).restore();

    expect(container.read(authProvider), isA<AuthNeedsBusiness>());
  });

  test('restore with nothing stored is signed out, with no error shown', () async {
    final container = containerWith();

    await container.read(authProvider.notifier).restore();

    final state = container.read(authProvider);
    expect(state, isA<AuthSignedOut>());
    expect((state as AuthSignedOut).error, isNull);
  });

  test('signing out clears the token and can carry a reason', () async {
    final container = containerWith();
    api.loginResult = sessionWith();
    await container.read(authProvider.notifier).signIn('sam', 'pw');

    await container.read(authProvider.notifier).signOut(reason: 'Session expired');

    expect(store.clearCount, 1);
    expect((container.read(authProvider) as AuthSignedOut).error, 'Session expired');
  });
}
```

- [ ] **Step 3: Run them to watch them fail**

Run: `fvm flutter test test/auth/auth_notifier_test.dart`
Expected: FAIL — `auth_notifier.dart` and `token_store.dart` do not exist.

- [ ] **Step 4: Write `token_store.dart`**

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What survives an app restart. The token is a bearer credential for a
/// business's customer records, so it lives in the Keychain / Keystore rather
/// than in SharedPreferences, which is plaintext on disk.
class StoredAuth {
  const StoredAuth({
    required this.token,
    required this.name,
    required this.role,
    required this.businessIds,
    required this.businessId,
  });

  final String token;
  final String name;
  final String role;
  final List<String> businessIds;

  /// The business chosen for this session. Null only while the picker is up.
  final String? businessId;

  StoredAuth withBusiness(String id) => StoredAuth(
        token: token,
        name: name,
        role: role,
        businessIds: businessIds,
        businessId: id,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'name': name,
        'role': role,
        'businessIds': businessIds,
        'businessId': businessId,
      };

  factory StoredAuth.fromJson(Map<String, dynamic> json) => StoredAuth(
        token: json['token'] as String,
        name: (json['name'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'staff',
        businessIds:
            ((json['businessIds'] as List?) ?? const []).map((e) => e as String).toList(),
        businessId: json['businessId'] as String?,
      );
}

abstract class TokenStore {
  Future<StoredAuth?> read();
  Future<void> write(StoredAuth auth);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'qwallet_scan_auth';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredAuth?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return StoredAuth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A payload written by an older build, or corrupted. Treat it as no
      // session rather than crashing on launch, which would be unrecoverable
      // without reinstalling.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredAuth auth) =>
      _storage.write(key: _key, value: jsonEncode(auth.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
```

- [ ] **Step 5: Write `auth_notifier.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'token_store.dart';

sealed class AuthState {
  const AuthState();
}

/// Before `restore()` has finished. The router holds on this so a signed-in
/// user never sees the login screen flash past on launch.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.error});

  /// Shown on the login screen. Null on a first launch or a deliberate sign-out.
  final String? error;
}

class AuthNeedsBusiness extends AuthState {
  const AuthNeedsBusiness(this.auth);
  final StoredAuth auth;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.auth);

  /// `auth.businessId` is non-null in this state — that is what the state means.
  final StoredAuth auth;
}

const _rolesAllowed = {'admin', 'business', 'staff'};

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthLoading();

  TokenStore get _store => ref.read(tokenStoreProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  /// Called once at startup.
  Future<void> restore() async {
    final stored = await _store.read();
    if (stored == null) {
      state = const AuthSignedOut();
      return;
    }
    state = stored.businessId == null
        ? AuthNeedsBusiness(stored)
        : AuthSignedIn(stored);
  }

  Future<void> signIn(String identifier, String password) async {
    state = const AuthLoading();
    try {
      final session = await _api.login(identifier: identifier, password: password);

      // Both refusals happen before anything is written: a rejected sign-in
      // must not leave a token behind that `restore()` would pick up.
      if (!_rolesAllowed.contains(session.role)) {
        state = const AuthSignedOut(
          error: 'This app is for staff and business owners.',
        );
        return;
      }
      if (session.businessIds.isEmpty) {
        state = const AuthSignedOut(
          error: 'This account is not linked to a business. Ask the owner to add you.',
        );
        return;
      }

      final single = session.businessIds.length == 1 ? session.businessIds.first : null;
      final auth = StoredAuth(
        token: session.token,
        name: session.name,
        role: session.role,
        businessIds: session.businessIds,
        businessId: single,
      );
      await _store.write(auth);
      state = single == null ? AuthNeedsBusiness(auth) : AuthSignedIn(auth);
    } on ApiException catch (e) {
      state = AuthSignedOut(error: e.message);
    }
  }

  Future<void> chooseBusiness(String businessId) async {
    final current = state;
    final auth = switch (current) {
      AuthNeedsBusiness(:final auth) => auth,
      AuthSignedIn(:final auth) => auth,
      _ => null,
    };
    if (auth == null) return;

    final updated = auth.withBusiness(businessId);
    await _store.write(updated);
    state = AuthSignedIn(updated);
  }

  Future<void> signOut({String? reason}) async {
    await _store.clear();
    state = AuthSignedOut(error: reason);
  }

  /// The token for the HTTP layer, or null when signed out.
  String? get token => switch (state) {
        AuthNeedsBusiness(:final auth) => auth.token,
        AuthSignedIn(:final auth) => auth.token,
        _ => null,
      };
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// The business every API call needs, or null when there isn't one yet.
final businessIdProvider = Provider<String?>((ref) {
  final state = ref.watch(authProvider);
  return state is AuthSignedIn ? state.auth.businessId : null;
});
```

- [ ] **Step 6: Wire the real client provider**

Replace the placeholder at the bottom of `lib/api/api_client.dart`:

```dart
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.qwallet.me',
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
```

Add `import '../auth/auth_notifier.dart';` at the top of that file.

- [ ] **Step 7: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: all suites pass, including the 10 new auth tests; analyze clean.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Hold auth state, and keep the token in the keychain"
```

---

### Task 5: Router, login screen and business picker

**Files:**
- Create: `lib/router.dart`, `lib/app.dart`, `lib/auth/login_screen.dart`,
  `lib/auth/business_picker_screen.dart`, `lib/ui/message_view.dart`
- Modify: `lib/main.dart`
- Test: `test/widget/login_screen_test.dart`

**Interfaces:**
- Consumes: `authProvider`, `AuthState` variants, `apiClientProvider`.
- Produces: `final routerProvider = Provider<GoRouter>(...)` with routes
  `/login`, `/choose-business`, `/scan`, `/logs`; `MessageView({required IconData icon, required String title, String? detail, VoidCallback? onRetry})`.

- [ ] **Step 1: Write the failing widget tests**

`test/widget/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/session.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/auth/login_screen.dart';
import 'package:qwallet_scan/auth/token_store.dart';

import '../support/fake_api_client.dart';

void main() {
  late FakeApiClient api;
  late FakeTokenStore store;

  Future<void> pumpLogin(WidgetTester tester) async {
    api = FakeApiClient();
    store = FakeTokenStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
  }

  testWidgets('the identifier field says a mobile number works too', (tester) async {
    await pumpLogin(tester);

    // Staff can be issued a mobile and no email; a field labelled "Email" would
    // read as "you cannot sign in".
    expect(find.text('Email or mobile number'), findsOneWidget);
  });

  testWidgets('signing in sends what was typed', (tester) async {
    await pumpLogin(tester);
    api.loginResult = const Session(
      token: 'jwt',
      userId: 7,
      email: 's@x.qa',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
    );

    await tester.enterText(find.byKey(const Key('identifier')), 'sam@shop.qa');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.loginCalls.single.identifier, 'sam@shop.qa');
    expect(api.loginCalls.single.password, 'pw');
  });

  testWidgets('a failure is shown on the screen, not swallowed', (tester) async {
    await pumpLogin(tester);
    api.loginError = ApiException(ApiErrorKind.unauthorized, 'Invalid credentials');

    await tester.enterText(find.byKey(const Key('identifier')), 'sam');
    await tester.enterText(find.byKey(const Key('password')), 'no');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('empty fields are refused without calling the API', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.loginCalls, isEmpty);
    expect(find.text('Enter your email or mobile number'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to watch it fail**

Run: `fvm flutter test test/widget/login_screen_test.dart`
Expected: FAIL — `login_screen.dart` does not exist.

- [ ] **Step 3: Write `lib/ui/message_view.dart`**

```dart
import 'package:flutter/material.dart';

/// The one way this app says "there is nothing here" or "that did not work".
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write `lib/auth/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Local, not derived from AuthLoading. That state also means "the app is
  /// still restoring a session at launch", and a login screen that reads it as
  /// "signing in" opens with a button that spins and can never be pressed.
  bool _submitting = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(authProvider.notifier)
          .signIn(_identifier.text.trim(), _password.text);
    } finally {
      // A successful sign-in routes away and this widget is gone; the guard is
      // for the refusals, which stay on this screen.
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final error = state is AuthSignedOut ? state.error : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Qwallet Scan', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to stamp and redeem cards.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('identifier'),
                      controller: _identifier,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        // Staff issued only a mobile number have no email to
                        // type; the API matches on either.
                        labelText: 'Email or mobile number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter your email or mobile number'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: true,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write `lib/auth/business_picker_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'auth_notifier.dart';

/// Names for the ids in the token, best-effort. A failed lookup falls back to
/// the id: not being able to read a name must not lock someone out of scanning.
final _businessNamesProvider =
    FutureProvider.autoDispose.family<String, String>((ref, businessId) async {
  try {
    return await ref.read(apiClientProvider).fetchBusinessName(businessId);
  } catch (_) {
    return businessId;
  }
});

class BusinessPickerScreen extends ConsumerWidget {
  const BusinessPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProvider);
    final ids = switch (state) {
      AuthNeedsBusiness(:final auth) => auth.businessIds,
      AuthSignedIn(:final auth) => auth.businessIds,
      _ => const <String>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a shop'),
        actions: [
          TextButton(
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: ids.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final id = ids[i];
          final name = ref.watch(_businessNamesProvider(id));
          return ListTile(
            // `value`, not `valueOrNull`: Riverpod 3 dropped the latter, and
            // `value` is already nullable while the lookup is in flight.
            title: Text(name.value ?? id),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(authProvider.notifier).chooseBusiness(id),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Write `lib/router.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_notifier.dart';
import 'auth/business_picker_screen.dart';
import 'auth/login_screen.dart';
import 'logs/logs_screen.dart';
import 'scan/scan_screen.dart';

/// Rebuilds the router's redirect whenever auth changes, so no screen has to
/// ask whether it should be on screen.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/scan',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, goState) {
      final auth = ref.read(authProvider);
      final path = goState.matchedLocation;

      return switch (auth) {
        // Nothing has been decided yet; hold wherever we are. main.dart shows a
        // splash until restore() completes.
        AuthLoading() => null,
        AuthSignedOut() => path == '/login' ? null : '/login',
        AuthNeedsBusiness() => path == '/choose-business' ? null : '/choose-business',
        AuthSignedIn() =>
          (path == '/login' || path == '/choose-business') ? '/scan' : null,
      };
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/choose-business', builder: (_, _) => const BusinessPickerScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(path: '/logs', builder: (_, _) => const LogsScreen()),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}
```

- [ ] **Step 7: Write `lib/app.dart` and `lib/main.dart`**

`lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_notifier.dart';
import 'router.dart';

class QwalletScanApp extends ConsumerStatefulWidget {
  const QwalletScanApp({super.key});

  @override
  ConsumerState<QwalletScanApp> createState() => _QwalletScanAppState();
}

class _QwalletScanAppState extends ConsumerState<QwalletScanApp> {
  @override
  void initState() {
    super.initState();
    // After the first frame: restore() writes to a provider, which cannot
    // happen during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorSchemeSeed: const Color(0xFF008CB4),
      useMaterial3: true,
    );

    if (ref.watch(authProvider) is AuthLoading) {
      return MaterialApp(
        theme: theme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: 'Qwallet Scan',
      theme: theme,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
```

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: QwalletScanApp()));
}
```

- [ ] **Step 8: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: all suites pass. `scan_screen.dart` and `logs_screen.dart` do not
exist yet — create both now as one-line placeholders so the router compiles:

```dart
// lib/scan/scan_screen.dart
import 'package:flutter/material.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Scan')));
}
```

```dart
// lib/logs/logs_screen.dart
import 'package:flutter/material.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Logs')));
}
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add sign-in, the shop picker, and the routing that guards them"
```

---

### Task 6: Card id parsing and scan state

**Files:**
- Create: `lib/scan/card_id_parser.dart`, `lib/scan/scan_notifier.dart`
- Test: `test/scan/card_id_parser_test.dart`, `test/scan/scan_notifier_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `LoyaltyCard`, `ApiException`, `businessIdProvider`.
- Produces:
  - `String? parseCardId(String raw)`
  - `sealed class ScanState` with `ScanIdle`, `ScanLoading`, `ScanFound(LoyaltyCard card, {String? actionError, bool busy})`, `ScanFailed(String message)`
  - `class ScanNotifier extends Notifier<ScanState>` with `Future<void> lookUp(String raw)`, `void reset()`, and the action methods added in Tasks 8-9
  - `final scanProvider = NotifierProvider<ScanNotifier, ScanState>(ScanNotifier.new)`

- [ ] **Step 1: Write the failing parser tests**

`test/scan/card_id_parser_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to watch it fail**

Run: `fvm flutter test test/scan/card_id_parser_test.dart`
Expected: FAIL — `card_id_parser.dart` does not exist.

- [ ] **Step 3: Write the parser**

`lib/scan/card_id_parser.dart`:

```dart
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
```

- [ ] **Step 4: Verify the parser**

Run: `fvm flutter test test/scan/card_id_parser_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Write the failing scan-state tests**

`test/scan/scan_notifier_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard rewardCard({int stampCount = 3, int rewardsAvailable = 0}) => LoyaltyCard(
      cardId: 'ABC1234567',
      businessId: 'biz-1',
      userName: 'Ali',
      userEmail: 'a@b.qa',
      userPhone: null,
      templateType: 'reward',
      stampCount: stampCount,
      rewardsAvailable: rewardsAvailable,
      stampsRequired: 10,
      rewardDescription: 'A free flat white',
      businessName: 'Wake',
      pointsBalance: 0,
      pointsExpiry: null,
      membershipNumber: null,
      membershipCategory: null,
      membershipExpiry: null,
    );

void main() {
  late FakeApiClient api;

  ProviderContainer containerWith() {
    api = FakeApiClient();
    return ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        businessIdProvider.overrideWithValue('biz-1'),
      ],
    );
  }

  test('a good code loads the card', () async {
    final container = containerWith();
    api.card = rewardCard();

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    final state = container.read(scanProvider);
    expect(state, isA<ScanFound>());
    expect((state as ScanFound).card.cardId, 'ABC1234567');
    expect(api.fetchedCardIds, ['ABC1234567']);
  });

  test('an unrecognised code never reaches the API', () async {
    final container = containerWith();

    await container.read(scanProvider.notifier).lookUp('https://example.com');

    expect(api.fetchedCardIds, isEmpty);
    expect(
      (container.read(scanProvider) as ScanFailed).message,
      'That QR code is not a loyalty card.',
    );
  });

  test('a 404 says the card does not exist', () async {
    final container = containerWith();
    api.cardError = ApiException(ApiErrorKind.notFound, 'No card found for this code.');

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    expect(
      (container.read(scanProvider) as ScanFailed).message,
      'No card found for this code.',
    );
  });

  test('a second scan arriving mid-lookup is ignored', () async {
    // The camera re-reads the same code several times a second. Without this
    // guard, one card held up to the lens fires a lookup per frame — and once
    // actions are wired in Task 8, a stamp per frame.
    final container = containerWith();
    api.card = rewardCard();
    final gate = Completer<void>();
    api.gate = gate.future;

    final first = container.read(scanProvider.notifier).lookUp('ABC1234567');
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    gate.complete();
    await first;

    expect(api.fetchedCardIds, hasLength(1));
  });

  test('reset returns to idle so the next customer can be scanned', () async {
    final container = containerWith();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    container.read(scanProvider.notifier).reset();

    expect(container.read(scanProvider), isA<ScanIdle>());
  });

  test('scanning without a chosen business fails loudly rather than silently', () async {
    api = FakeApiClient();
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        businessIdProvider.overrideWithValue(null),
      ],
    );

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    expect(api.fetchedCardIds, isEmpty);
    expect(container.read(scanProvider), isA<ScanFailed>());
  });
}
```

- [ ] **Step 6: Run to watch it fail**

Run: `fvm flutter test test/scan/scan_notifier_test.dart`
Expected: FAIL — `scan_notifier.dart` does not exist.

- [ ] **Step 7: Write the notifier**

`lib/scan/scan_notifier.dart`:

```dart
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
```

- [ ] **Step 8: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Read a QR code into a card, once per scan"
```

---

### Task 7: The scan screen

**Files:**
- Create: `lib/scan/card_result_view.dart`
- Modify: `lib/scan/scan_screen.dart` (replacing Task 5's placeholder)
- Modify: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Test: none of its own — the camera cannot be driven in a widget test. Its
  parts are tested in Tasks 6, 8 and 9.

**Interfaces:**
- Consumes: `scanProvider`, `ScanState` variants, `MessageView`.
- Produces: `CardResultView({required LoyaltyCard card})`, which dispatches on
  `templateType` to the action widgets built in Tasks 8-9.

- [ ] **Step 1: Declare the camera permission**

`ios/Runner/Info.plist` — add inside the top-level `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>Qwallet Scan uses the camera to read loyalty card QR codes.</string>
```

`android/app/src/main/AndroidManifest.xml` — add above `<application>`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

- [ ] **Step 2: Write `card_result_view.dart` with its dispatch**

`lib/scan/card_result_view.dart`. The three action widgets arrive in Tasks 8-9;
create them now as stubs returning `const SizedBox.shrink()` so this compiles,
and Tasks 8 and 9 replace their bodies.

```dart
import 'package:flutter/material.dart';

import '../api/models/loyalty_card.dart';
import '../ui/message_view.dart';
import 'membership_actions.dart';
import 'points_actions.dart';
import 'reward_actions.dart';

/// The customer, then whatever can be done for their card type.
class CardResultView extends StatelessWidget {
  const CardResultView({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          card.userName?.trim().isNotEmpty == true ? card.userName! : 'Customer',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (card.userEmail != null)
          Text(card.userEmail!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        switch (card.templateType) {
          'reward' => RewardActions(card: card),
          'points' => PointsActions(card: card),
          'membership' => MembershipActions(card: card),
          _ => const MessageView(
              icon: Icons.help_outline,
              title: "This card type isn't supported in this app",
              detail: 'Use the web dashboard for this customer.',
            ),
        },
      ],
    );
  }
}
```

- [ ] **Step 3: Write the scan screen**

`lib/scan/scan_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../auth/auth_notifier.dart';
import '../ui/message_view.dart';
import 'card_result_view.dart';
import 'scan_notifier.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _manualId = TextEditingController();

  @override
  void dispose() {
    _manualId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          IconButton(
            tooltip: 'Scan log',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => context.push('/logs'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: switch (state) {
        ScanIdle() => _camera(),
        ScanLoading() => const Center(child: CircularProgressIndicator()),
        ScanFound() => CardResultView(card: state.card),
        ScanFailed() => MessageView(
            icon: Icons.error_outline,
            title: state.message,
            onRetry: () => ref.read(scanProvider.notifier).reset(),
          ),
      },
      bottomNavigationBar: state is ScanIdle
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonal(
                  onPressed: () => ref.read(scanProvider.notifier).reset(),
                  child: const Text('Scan next'),
                ),
              ),
            ),
    );
  }

  Widget _camera() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              // The notifier's own guard stops repeats; this only skips frames
              // that decoded to nothing at all.
              if (raw != null) ref.read(scanProvider.notifier).lookUp(raw);
            },
            onDetectError: (error, _) {
              // A decode failure on one frame is not worth telling anyone about;
              // the next frame will try again.
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualId,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Or type the card ID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => ref.read(scanProvider.notifier).lookUp(v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(scanProvider.notifier).lookUp(_manualId.text),
                child: const Text('Look up'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Verify it builds and the suite still passes**

Run: `fvm flutter test && fvm flutter analyze`
Expected: pass and clean. The stub action widgets render nothing yet.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Put the camera, manual entry and the card result on screen"
```

---

### Task 8: Reward actions

**Files:**
- Create: `lib/ui/async_button.dart`
- Modify: `lib/scan/reward_actions.dart` (replacing Task 7's stub),
  `lib/scan/scan_notifier.dart` (add the three action methods)
- Test: `test/widget/reward_actions_test.dart`, and additions to
  `test/scan/scan_notifier_test.dart`

**Interfaces:**
- Consumes: `ScanFound`, `CardActionResult`, `apiClientProvider`.
- Produces: on `ScanNotifier` —
  `Future<void> addStamps(int increment)`, `Future<void> addToRewards()`,
  `Future<void> redeem()`; and `RewardActions({required LoyaltyCard card})`.

- [ ] **Step 1: Write the failing notifier-action tests**

Append to `test/scan/scan_notifier_test.dart`, inside `main()`:

```dart
  test('adding stamps renders what the server returned, not a local guess', () async {
    final container = containerWith();
    api.card = rewardCard(stampCount: 3);
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    // The server banked a milestone on the way: 3 + 2 would be 5, but it is not.
    api.actionResult =
        const CardActionResult(stampCount: 0, stampsRequired: 10, rewardsAvailable: 1);

    await container.read(scanProvider.notifier).addStamps(2);

    final state = container.read(scanProvider) as ScanFound;
    expect(state.card.stampCount, 0);
    expect(state.card.rewardsAvailable, 1);
    expect(api.actions, ['addStamps:2']);
  });

  test("a refused action keeps the card up and shows the server's words", () async {
    final container = containerWith();
    api.card = rewardCard(stampCount: 3);
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionError =
        ApiException(ApiErrorKind.badRequest, 'Stamps not yet complete (3/10)');

    await container.read(scanProvider.notifier).addToRewards();

    final state = container.read(scanProvider) as ScanFound;
    expect(state.actionError, 'Stamps not yet complete (3/10)');
    expect(state.card.stampCount, 3);
    expect(state.busy, isFalse);
  });

  test('a second action while one is in flight is ignored', () async {
    final container = containerWith();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionResult =
        const CardActionResult(stampCount: 4, stampsRequired: 10, rewardsAvailable: 0);
    final gate = Completer<void>();
    api.gate = gate.future;

    final first = container.read(scanProvider.notifier).addStamps(1);
    await container.read(scanProvider.notifier).addStamps(1);
    gate.complete();
    await first;

    expect(api.actions, ['addStamps:1']);
  });

  test('redeem posts and updates', () async {
    final container = containerWith();
    api.card = rewardCard(rewardsAvailable: 1);
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionResult =
        const CardActionResult(stampCount: 0, stampsRequired: 10, rewardsAvailable: 0);

    await container.read(scanProvider.notifier).redeem();

    expect(api.actions, ['redeem']);
    expect((container.read(scanProvider) as ScanFound).card.rewardsAvailable, 0);
  });
```

Add `import 'package:qwallet_scan/api/models/loyalty_card.dart';` if it is not
already imported, and `import 'dart:async';` for `Completer`.

- [ ] **Step 2: Run to watch them fail**

Run: `fvm flutter test test/scan/scan_notifier_test.dart`
Expected: FAIL — `addStamps`, `addToRewards`, `redeem` are not defined.

- [ ] **Step 3: Add the action methods**

In `lib/scan/scan_notifier.dart`, inside `ScanNotifier`:

```dart
  Future<void> addStamps(int increment) => _act(
        (api, card, businessId) => api.addStamps(
          cardId: card.cardId,
          businessId: businessId,
          increment: increment,
        ),
      );

  Future<void> addToRewards() => _act(
        (api, card, businessId) =>
            api.addToRewards(cardId: card.cardId, businessId: businessId),
      );

  Future<void> redeem() => _act(
        (api, card, businessId) =>
            api.redeem(cardId: card.cardId, businessId: businessId),
      );

  /// The shape every reward action takes: only from a loaded card, only one at
  /// a time, and the new counts come from the response — never from arithmetic
  /// here. A multi-milestone card can bank a reward and reset to zero on an
  /// ordinary stamp, which no local guess would predict.
  Future<void> _act(
    Future<CardActionResult> Function(ApiClient, LoyaltyCard, String) call,
  ) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await call(ref.read(apiClientProvider), current.card, businessId);
      state = ScanFound(
        current.card.withRewardState(
          stampCount: result.stampCount,
          rewardsAvailable: result.rewardsAvailable,
          stampsRequired: result.stampsRequired,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }
```

- [ ] **Step 4: Add `withRewardState` to `LoyaltyCard`**

In `lib/api/models/loyalty_card.dart`, inside the class:

```dart
  /// A copy carrying the counts an action returned. Only these three move —
  /// the customer and the card's identity do not change under a stamp.
  LoyaltyCard withRewardState({
    required int stampCount,
    required int rewardsAvailable,
    required int stampsRequired,
  }) =>
      LoyaltyCard(
        cardId: cardId,
        businessId: businessId,
        userName: userName,
        userEmail: userEmail,
        userPhone: userPhone,
        templateType: templateType,
        stampCount: stampCount,
        rewardsAvailable: rewardsAvailable,
        stampsRequired: stampsRequired,
        rewardDescription: rewardDescription,
        businessName: businessName,
        pointsBalance: pointsBalance,
        pointsExpiry: pointsExpiry,
        membershipNumber: membershipNumber,
        membershipCategory: membershipCategory,
        membershipExpiry: membershipExpiry,
      );
```

Add `import '../api/api_client.dart';` to `scan_notifier.dart` if it is not
already there.

- [ ] **Step 5: Verify the notifier tests pass**

Run: `fvm flutter test test/scan/scan_notifier_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 6: Write the failing widget tests**

`test/widget/reward_actions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/reward_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard card({int stampCount = 3, int rewardsAvailable = 0}) => LoyaltyCard(
      cardId: 'ABC1234567',
      businessId: 'biz-1',
      userName: 'Ali',
      userEmail: 'a@b.qa',
      userPhone: null,
      templateType: 'reward',
      stampCount: stampCount,
      rewardsAvailable: rewardsAvailable,
      stampsRequired: 10,
      rewardDescription: 'A free flat white',
      businessName: 'Wake',
      pointsBalance: 0,
      pointsExpiry: null,
      membershipNumber: null,
      membershipCategory: null,
      membershipExpiry: null,
    );

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester, LoyaltyCard c) async {
    api = FakeApiClient();
    api.card = c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp(home: Scaffold(body: RewardActions(card: c))),
      ),
    );
    // This widget only ever renders inside ScanFound, so the notifier is put
    // there too. Without it the buttons are correctly inert — _act refuses to
    // run against a notifier holding no card — and every action test would be
    // asserting on a state the app never reaches.
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the stamp count and the reward on offer', (tester) async {
    await pump(tester, card(stampCount: 7));

    expect(find.text('7 / 10 stamps'), findsOneWidget);
    expect(find.text('A free flat white'), findsOneWidget);
  });

  testWidgets('all three actions are tappable on a part-filled card', (tester) async {
    // Neither Add to Rewards nor Redeem is gated on a local rule: the
    // add-reward threshold on a multi-milestone card is a cumulative sum this
    // app is not given, and redeem is legal straight off a completed card with
    // no banked rewards. The server decides; see the spec.
    await pump(tester, card(stampCount: 3, rewardsAvailable: 0));

    for (final label in ['Add Stamps', 'Add to Rewards', 'Redeem']) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, label),
      );
      expect(button.onPressed, isNotNull, reason: '$label must stay tappable');
    }
  });

  testWidgets('Redeem asks before it takes anything away', (tester) async {
    await pump(tester, card(rewardsAvailable: 1));

    await tester.tap(find.widgetWithText(FilledButton, 'Redeem'));
    await tester.pumpAndSettle();

    expect(find.text('Redeem a reward?'), findsOneWidget);
    expect(api.actions, isEmpty, reason: 'nothing until it is confirmed');
  });

  testWidgets('confirming the dialog performs the redemption', (tester) async {
    await pump(tester, card(rewardsAvailable: 1));
    api.actionResult =
        const CardActionResult(stampCount: 0, stampsRequired: 10, rewardsAvailable: 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Redeem'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Redeem'));
    await tester.pumpAndSettle();

    expect(api.actions, ['redeem']);
  });

  testWidgets('the increment can be raised and is what gets sent', (tester) async {
    await pump(tester, card());
    api.actionResult =
        const CardActionResult(stampCount: 6, stampsRequired: 10, rewardsAvailable: 0);

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Stamps'));
    await tester.pumpAndSettle();

    expect(api.actions, ['addStamps:3']);
  });

  testWidgets('the increment never goes below one', (tester) async {
    await pump(tester, card());

    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Run to watch them fail**

Run: `fvm flutter test test/widget/reward_actions_test.dart`
Expected: FAIL — `RewardActions` is still the stub.

- [ ] **Step 8: Write `lib/ui/async_button.dart`**

```dart
import 'package:flutter/material.dart';

/// A filled button that shows a spinner in place of its label while [busy], and
/// refuses taps meanwhile. Every action in this app is a network call that must
/// not be fired twice.
class AsyncButton extends StatelessWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final onTap = busy ? null : onPressed;

    return tonal
        ? FilledButton.tonal(onPressed: onTap, child: child)
        : FilledButton(onPressed: onTap, child: child);
  }
}
```

- [ ] **Step 9: Write `lib/scan/reward_actions.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'scan_notifier.dart';

class RewardActions extends ConsumerStatefulWidget {
  const RewardActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<RewardActions> createState() => _RewardActionsState();
}

class _RewardActionsState extends ConsumerState<RewardActions> {
  int _increment = 1;

  Future<void> _confirmRedeem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem a reward?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(scanProvider.notifier).redeem();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${card.stampCount} / ${card.stampsRequired} stamps',
            style: theme.textTheme.titleLarge),
        if (card.rewardDescription.isNotEmpty)
          Text(card.rewardDescription, style: theme.textTheme.bodyMedium),
        if (card.rewardsAvailable > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${card.rewardsAvailable} reward${card.rewardsAvailable == 1 ? '' : 's'} waiting',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove),
              onPressed: _increment > 1 ? () => setState(() => _increment--) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('$_increment', style: theme.textTheme.headlineSmall),
            ),
            IconButton.outlined(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _increment++),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AsyncButton(
          label: 'Add Stamps',
          busy: busy,
          onPressed: () => ref.read(scanProvider.notifier).addStamps(_increment),
        ),
        const SizedBox(height: 8),
        // Not disabled on stampCount >= stampsRequired: on a multi-milestone
        // card the real threshold is the cumulative total of every rung so far,
        // and this screen is not given the milestones to compute it. The server
        // knows, and its refusal is readable.
        AsyncButton(
          label: 'Add to Rewards',
          tonal: true,
          busy: busy,
          onPressed: () => ref.read(scanProvider.notifier).addToRewards(),
        ),
        const SizedBox(height: 8),
        // Not disabled on rewardsAvailable == 0 either: the API also allows
        // redeeming straight off a completed card, so a 10/10 card with nothing
        // banked is legitimately redeemable.
        AsyncButton(
          label: 'Redeem',
          tonal: true,
          busy: busy,
          onPressed: _confirmRedeem,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
```

- [ ] **Step 10: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add stamps, bank rewards and redeem, with the server deciding"
```

---

### Task 9: Points and membership actions

**Files:**
- Modify: `lib/scan/points_actions.dart`, `lib/scan/membership_actions.dart`
  (replacing Task 7's stubs), `lib/scan/scan_notifier.dart`
- Test: `test/widget/points_membership_test.dart`

**Interfaces:**
- Consumes: `PointsResult`, `MembershipResult`, `ScanFound`.
- Produces: on `ScanNotifier` — `Future<void> adjustPoints(int points)`,
  `Future<void> renewMembership(int months)`; and the widgets
  `PointsActions({required LoyaltyCard card})`,
  `MembershipActions({required LoyaltyCard card})`.

- [ ] **Step 1: Write the failing widget tests**

`test/widget/points_membership_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/scan/membership_actions.dart';
import 'package:qwallet_scan/scan/points_actions.dart';
import 'package:qwallet_scan/scan/scan_notifier.dart';

import '../support/fake_api_client.dart';

LoyaltyCard base({
  required String type,
  int pointsBalance = 0,
  String? membershipNumber,
  String? membershipCategory,
  DateTime? membershipExpiry,
}) =>
    LoyaltyCard(
      cardId: 'ABC1234567',
      businessId: 'biz-1',
      userName: 'Ali',
      userEmail: null,
      userPhone: null,
      templateType: type,
      stampCount: 0,
      rewardsAvailable: 0,
      stampsRequired: 0,
      rewardDescription: '',
      businessName: 'Wake',
      pointsBalance: pointsBalance,
      pointsExpiry: null,
      membershipNumber: membershipNumber,
      membershipCategory: membershipCategory,
      membershipExpiry: membershipExpiry,
    );

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester, LoyaltyCard c, Widget child) async {
    api = FakeApiClient();
    api.card = c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    // Same reason as the reward tests: these widgets only render inside
    // ScanFound, and their buttons are inert without a loaded card.
    await tester.container().read(scanProvider.notifier).lookUp(c.cardId);
    await tester.pumpAndSettle();
  }

  group('PointsActions', () {
    testWidgets('shows the balance', (tester) async {
      final c = base(type: 'points', pointsBalance: 250);
      await pump(tester, c, PointsActions(card: c));

      expect(find.text('250 points'), findsOneWidget);
    });

    testWidgets('Add sends a positive amount', (tester) async {
      final c = base(type: 'points');
      await pump(tester, c, PointsActions(card: c));
      api.pointsResult = const PointsResult(pointsBalance: 50, pointsExpiry: null);

      await tester.enterText(find.byKey(const Key('points-amount')), '50');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Points'));
      await tester.pumpAndSettle();

      expect(api.actions, ['adjustPoints:50']);
    });

    testWidgets('Deduct sends the negative of the same amount', (tester) async {
      final c = base(type: 'points', pointsBalance: 100);
      await pump(tester, c, PointsActions(card: c));
      api.pointsResult = const PointsResult(pointsBalance: 70, pointsExpiry: null);

      await tester.enterText(find.byKey(const Key('points-amount')), '30');
      await tester.tap(find.widgetWithText(FilledButton, 'Deduct Points'));
      await tester.pumpAndSettle();

      expect(api.actions, ['adjustPoints:-30']);
    });

    testWidgets('a non-numeric amount is refused before any call', (tester) async {
      final c = base(type: 'points');
      await pump(tester, c, PointsActions(card: c));

      await tester.enterText(find.byKey(const Key('points-amount')), 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Points'));
      await tester.pumpAndSettle();

      expect(api.actions, isEmpty);
      expect(find.text('Enter a number of points'), findsOneWidget);
    });
  });

  group('MembershipActions', () {
    testWidgets('shows the number, category and expiry', (tester) async {
      final c = base(
        type: 'membership',
        membershipNumber: 'MBR-0007',
        membershipCategory: 'Gold',
        membershipExpiry: DateTime.utc(2027, 1, 31),
      );
      await pump(tester, c, MembershipActions(card: c));

      expect(find.text('MBR-0007'), findsOneWidget);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.textContaining('2027'), findsOneWidget);
    });

    testWidgets('renewing sends the chosen number of months', (tester) async {
      final c = base(type: 'membership', membershipNumber: 'MBR-0007');
      await pump(tester, c, MembershipActions(card: c));
      api.membershipResult = MembershipResult(
        membershipNumber: 'MBR-0007',
        membershipCategory: null,
        membershipExpiry: DateTime.utc(2027, 9, 7),
      );

      await tester.tap(find.text('12 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Renew'));
      await tester.pumpAndSettle();

      expect(api.actions, ['renewMembership:12']);
    });

    testWidgets('a card with no expiry says so rather than showing a blank',
        (tester) async {
      final c = base(type: 'membership', membershipNumber: 'MBR-0007');
      await pump(tester, c, MembershipActions(card: c));

      expect(find.text('No expiry set'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to watch them fail**

Run: `fvm flutter test test/widget/points_membership_test.dart`
Expected: FAIL — both widgets are still stubs.

- [ ] **Step 3: Add the two notifier methods**

In `lib/scan/scan_notifier.dart`, inside `ScanNotifier`:

```dart
  /// [points] is signed: the Deduct button passes a negative.
  Future<void> adjustPoints(int points) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await ref.read(apiClientProvider).adjustPoints(
            cardId: current.card.cardId,
            businessId: businessId,
            points: points,
          );
      state = ScanFound(
        current.card.withPointsState(
          pointsBalance: result.pointsBalance,
          pointsExpiry: result.pointsExpiry,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }

  Future<void> renewMembership(int months) async {
    final current = state;
    if (current is! ScanFound || current.busy) return;
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const ScanFailed('No shop selected. Sign in again.');
      return;
    }

    state = current.copyWith(busy: true);
    try {
      final result = await ref.read(apiClientProvider).renewMembership(
            cardId: current.card.cardId,
            businessId: businessId,
            expiryMonths: months,
          );
      state = ScanFound(
        current.card.withMembershipState(
          membershipNumber: result.membershipNumber,
          membershipCategory: result.membershipCategory,
          membershipExpiry: result.membershipExpiry,
        ),
      );
    } on ApiException catch (e) {
      state = ScanFound(current.card, actionError: e.message);
    }
  }
```

- [ ] **Step 4: Add the two copy helpers to `LoyaltyCard`**

In `lib/api/models/loyalty_card.dart`, inside the class:

```dart
  LoyaltyCard withPointsState({
    required int pointsBalance,
    required DateTime? pointsExpiry,
  }) =>
      LoyaltyCard(
        cardId: cardId,
        businessId: businessId,
        userName: userName,
        userEmail: userEmail,
        userPhone: userPhone,
        templateType: templateType,
        stampCount: stampCount,
        rewardsAvailable: rewardsAvailable,
        stampsRequired: stampsRequired,
        rewardDescription: rewardDescription,
        businessName: businessName,
        pointsBalance: pointsBalance,
        pointsExpiry: pointsExpiry,
        membershipNumber: membershipNumber,
        membershipCategory: membershipCategory,
        membershipExpiry: membershipExpiry,
      );

  LoyaltyCard withMembershipState({
    required String? membershipNumber,
    required String? membershipCategory,
    required DateTime? membershipExpiry,
  }) =>
      LoyaltyCard(
        cardId: cardId,
        businessId: businessId,
        userName: userName,
        userEmail: userEmail,
        userPhone: userPhone,
        templateType: templateType,
        stampCount: stampCount,
        rewardsAvailable: rewardsAvailable,
        stampsRequired: stampsRequired,
        rewardDescription: rewardDescription,
        businessName: businessName,
        pointsBalance: pointsBalance,
        pointsExpiry: pointsExpiry,
        membershipNumber: membershipNumber,
        membershipCategory: membershipCategory,
        membershipExpiry: membershipExpiry,
      );
```

- [ ] **Step 5: Write `lib/scan/points_actions.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'scan_notifier.dart';

class PointsActions extends ConsumerStatefulWidget {
  const PointsActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<PointsActions> createState() => _PointsActionsState();
}

class _PointsActionsState extends ConsumerState<PointsActions> {
  final _amount = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit({required bool deduct}) {
    final parsed = int.tryParse(_amount.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _localError = 'Enter a number of points');
      return;
    }
    setState(() => _localError = null);
    ref.read(scanProvider.notifier).adjustPoints(deduct ? -parsed : parsed);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final serverError = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${card.pointsBalance} points', style: theme.textTheme.headlineMedium),
        if (card.pointsExpiry != null)
          Text(
            'Expires ${_formatDate(card.pointsExpiry!)}',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('points-amount'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Points',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        AsyncButton(
          label: 'Add Points',
          busy: busy,
          onPressed: () => _submit(deduct: false),
        ),
        const SizedBox(height: 8),
        AsyncButton(
          label: 'Deduct Points',
          tonal: true,
          busy: busy,
          onPressed: () => _submit(deduct: true),
        ),
        if (_localError != null || serverError != null) ...[
          const SizedBox(height: 12),
          Text(
            _localError ?? serverError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
```

- [ ] **Step 6: Write `lib/scan/membership_actions.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/loyalty_card.dart';
import '../ui/async_button.dart';
import 'scan_notifier.dart';

class MembershipActions extends ConsumerStatefulWidget {
  const MembershipActions({super.key, required this.card});

  final LoyaltyCard card;

  @override
  ConsumerState<MembershipActions> createState() => _MembershipActionsState();
}

class _MembershipActionsState extends ConsumerState<MembershipActions> {
  static const _options = [3, 6, 12];
  int _months = 3;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);
    final busy = state is ScanFound && state.busy;
    final error = state is ScanFound ? state.actionError : null;
    final card = state is ScanFound ? state.card : widget.card;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(card.membershipNumber ?? 'No membership number',
            style: theme.textTheme.headlineSmall),
        if (card.membershipCategory != null)
          Text(card.membershipCategory!, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          card.membershipExpiry == null
              ? 'No expiry set'
              : 'Expires ${_formatDate(card.membershipExpiry!)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Text('Renew for', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final months in _options)
              ChoiceChip(
                label: Text('$months months'),
                selected: _months == months,
                onSelected: (_) => setState(() => _months = months),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(
          label: 'Renew',
          busy: busy,
          onPressed: () => ref.read(scanProvider.notifier).renewMembership(_months),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
```

- [ ] **Step 7: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Act on points and membership cards, not just reward ones"
```

---

### Task 10: The scan log

**Files:**
- Create: `lib/logs/logs_notifier.dart`
- Modify: `lib/logs/logs_screen.dart` (replacing Task 5's placeholder)
- Test: `test/logs/logs_notifier_test.dart`, `test/widget/logs_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient.fetchScanLog`, `ScanLogPage`, `ScanLogEntry`,
  `businessIdProvider`.
- Produces:
  - `class LogsState { List<ScanLogEntry> entries; bool loading; bool loadingMore; bool hasMore; String? cursor; String? error; }`
  - `class LogsNotifier extends Notifier<LogsState>` with
    `Future<void> loadFirstPage()`, `Future<void> loadMore()`, `Future<void> refresh()`
  - `final logsProvider = NotifierProvider<LogsNotifier, LogsState>(LogsNotifier.new)`

- [ ] **Step 1: Write the failing notifier tests**

`test/logs/logs_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/logs/logs_notifier.dart';

import '../support/fake_api_client.dart';

ScanLogEntry entry(int id, {ScanLogType type = ScanLogType.stamp}) => ScanLogEntry(
      id: id,
      type: type,
      cardId: 'ABC1234567',
      staffName: 'Sam',
      customerName: 'Ali',
      stampsAdded: 1,
      stampsBefore: 0,
      stampsAfter: 1,
      loggedAt: DateTime.utc(2026, 9, 7, 10 - id),
    );

void main() {
  late FakeApiClient api;

  ProviderContainer containerWith() {
    api = FakeApiClient();
    return ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        businessIdProvider.overrideWithValue('biz-1'),
      ],
    );
  }

  test('the first page loads with no cursor', () async {
    final container = containerWith();
    api.logPages.add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'));

    await container.read(logsProvider.notifier).loadFirstPage();

    final state = container.read(logsProvider);
    expect(api.logCursors, [null]);
    expect(state.entries, hasLength(1));
    expect(state.hasMore, isTrue);
    expect(state.cursor, 'c1');
  });

  test('loadMore appends the next page and carries the cursor forward', () async {
    final container = containerWith();
    api.logPages
      ..add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'))
      ..add(ScanLogPage(entries: [entry(2)], hasMore: false, nextCursor: null));
    await container.read(logsProvider.notifier).loadFirstPage();

    await container.read(logsProvider.notifier).loadMore();

    final state = container.read(logsProvider);
    expect(api.logCursors, [null, 'c1']);
    expect(state.entries.map((e) => e.id), [1, 2]);
    expect(state.hasMore, isFalse);
  });

  test('loadMore does nothing once the last page is in', () async {
    final container = containerWith();
    api.logPages.add(ScanLogPage(entries: [entry(1)], hasMore: false, nextCursor: null));
    await container.read(logsProvider.notifier).loadFirstPage();

    await container.read(logsProvider.notifier).loadMore();

    expect(api.logCursors, hasLength(1));
  });

  test('refresh discards what was loaded and starts again', () async {
    final container = containerWith();
    api.logPages
      ..add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'))
      ..add(ScanLogPage(entries: [entry(9)], hasMore: false, nextCursor: null));
    await container.read(logsProvider.notifier).loadFirstPage();

    await container.read(logsProvider.notifier).refresh();

    final state = container.read(logsProvider);
    expect(state.entries.map((e) => e.id), [9]);
    expect(api.logCursors, [null, null]);
  });

  test('a failed first page reports the error and leaves the list empty', () async {
    final container = containerWith();
    api.logError = ApiException.network();

    await container.read(logsProvider.notifier).loadFirstPage();

    final state = container.read(logsProvider);
    expect(state.entries, isEmpty);
    expect(state.error, "Can't reach the server. Check your connection.");
    expect(state.loading, isFalse);
  });

  test('a failed second page keeps the rows already on screen', () async {
    // Losing thirty loaded rows because page two timed out would be worse than
    // the failure itself.
    final container = containerWith();
    api.logPages.add(ScanLogPage(entries: [entry(1)], hasMore: true, nextCursor: 'c1'));
    await container.read(logsProvider.notifier).loadFirstPage();
    api.logError = ApiException.network();

    await container.read(logsProvider.notifier).loadMore();

    final state = container.read(logsProvider);
    expect(state.entries, hasLength(1));
    expect(state.error, isNotNull);
  });
}
```

- [ ] **Step 2: Run to watch them fail**

Run: `fvm flutter test test/logs/logs_notifier_test.dart`
Expected: FAIL — `logs_notifier.dart` does not exist.

- [ ] **Step 3: Write the notifier**

`lib/logs/logs_notifier.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models/scan_log_entry.dart';
import '../auth/auth_notifier.dart';

class LogsState {
  const LogsState({
    this.entries = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.cursor,
    this.error,
  });

  final List<ScanLogEntry> entries;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? cursor;
  final String? error;

  LogsState copyWith({
    List<ScanLogEntry>? entries,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? cursor,
    String? error,
  }) =>
      LogsState(
        entries: entries ?? this.entries,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        cursor: cursor ?? this.cursor,
        error: error,
      );
}

class LogsNotifier extends Notifier<LogsState> {
  @override
  LogsState build() => const LogsState();

  Future<void> loadFirstPage() async {
    final businessId = ref.read(businessIdProvider);
    if (businessId == null) {
      state = const LogsState(error: 'No shop selected. Sign in again.');
      return;
    }

    state = const LogsState(loading: true);
    try {
      final page = await ref
          .read(apiClientProvider)
          .fetchScanLog(businessId: businessId);
      state = LogsState(
        entries: page.entries,
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } on ApiException catch (e) {
      state = LogsState(error: e.message);
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (!current.hasMore || current.loadingMore || current.cursor == null) return;

    final businessId = ref.read(businessIdProvider);
    if (businessId == null) return;

    state = current.copyWith(loadingMore: true);
    try {
      final page = await ref.read(apiClientProvider).fetchScanLog(
            businessId: businessId,
            cursor: current.cursor,
          );
      state = LogsState(
        entries: [...current.entries, ...page.entries],
        hasMore: page.hasMore,
        cursor: page.nextCursor,
      );
    } on ApiException catch (e) {
      // The rows already loaded stay: a failed page two must not empty the
      // screen.
      state = current.copyWith(loadingMore: false, error: e.message);
    }
  }

  Future<void> refresh() => loadFirstPage();
}

final logsProvider = NotifierProvider<LogsNotifier, LogsState>(LogsNotifier.new);
```

- [ ] **Step 4: Verify the notifier tests pass**

Run: `fvm flutter test test/logs/logs_notifier_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Write the failing screen tests**

`test/widget/logs_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/auth/auth_notifier.dart';
import 'package:qwallet_scan/logs/logs_screen.dart';

import '../support/fake_api_client.dart';

void main() {
  late FakeApiClient api;

  Future<void> pump(WidgetTester tester) async {
    api = FakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          businessIdProvider.overrideWithValue('biz-1'),
        ],
        child: const MaterialApp(home: LogsScreen()),
      ),
    );
  }

  testWidgets('an empty log says so instead of showing a blank screen',
      (tester) async {
    await pump(tester);
    api.logPages.add(
      const ScanLogPage(entries: [], hasMore: false, nextCursor: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry rather than looking empty',
      (tester) async {
    await pump(tester);
    api.logError = ApiException.network();
    await tester.pumpAndSettle();

    expect(find.text("Can't reach the server. Check your connection."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('rows show the customer and what happened', (tester) async {
    await pump(tester);
    api.logPages.add(
      ScanLogPage(
        entries: [
          ScanLogEntry(
            id: 1,
            type: ScanLogType.redemption,
            cardId: 'ABC1234567',
            staffName: 'Sam',
            customerName: 'Ali',
            stampsAdded: 10,
            stampsBefore: 10,
            stampsAfter: 0,
            loggedAt: DateTime.utc(2026, 9, 7, 9, 15),
          ),
        ],
        hasMore: false,
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Reward redeemed'), findsOneWidget);
    expect(find.textContaining('Sam'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run to watch them fail**

Run: `fvm flutter test test/widget/logs_screen_test.dart`
Expected: FAIL — `LogsScreen` is still Task 5's placeholder.

- [ ] **Step 7: Write the screen**

`lib/logs/logs_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/scan_log_entry.dart';
import '../ui/message_view.dart';
import 'logs_notifier.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(logsProvider.notifier).loadFirstPage();
    });
    _scroll.addListener(() {
      // 400px of runway, so the next page is usually in before the list ends.
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        ref.read(logsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan log')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(logsProvider.notifier).refresh(),
        child: switch (state) {
          LogsState(loading: true) => const Center(child: CircularProgressIndicator()),
          LogsState(entries: [], error: final e?) => MessageView(
              icon: Icons.cloud_off,
              title: e,
              onRetry: () => ref.read(logsProvider.notifier).loadFirstPage(),
            ),
          LogsState(entries: []) => const MessageView(
              icon: Icons.receipt_long,
              title: 'No scans yet',
              detail: 'Stamps and redemptions will appear here.',
            ),
          _ => _list(state),
        },
      ),
    );
  }

  Widget _list(LogsState state) {
    final rows = _withDayHeaders(state.entries);

    return ListView.builder(
      controller: _scroll,
      itemCount: rows.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final row = rows[i];
        return switch (row) {
          _DayHeader(:final label) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
          _EntryRow(:final entry) => ListTile(
              leading: Icon(
                entry.type == ScanLogType.redemption
                    ? Icons.redeem
                    : Icons.check_circle_outline,
              ),
              title: Text(entry.customerName ?? 'Customer'),
              subtitle: Text(
                '${entry.type == ScanLogType.redemption ? 'Reward redeemed' : '+${entry.stampsAdded} stamps'}'
                ' · ${entry.stampsBefore} → ${entry.stampsAfter}'
                '${entry.staffName != null ? ' · ${entry.staffName}' : ''}',
              ),
              trailing: Text(_formatTime(entry.loggedAt.toLocal())),
            ),
        };
      },
    );
  }
}

sealed class _Row {
  const _Row();
}

class _DayHeader extends _Row {
  const _DayHeader(this.label);
  final String label;
}

class _EntryRow extends _Row {
  const _EntryRow(this.entry);
  final ScanLogEntry entry;
}

/// Splits a flat, newest-first list into day sections. Dates are compared in
/// local time, which is what "today" means to the person reading.
List<_Row> _withDayHeaders(List<ScanLogEntry> entries) {
  final rows = <_Row>[];
  String? lastDay;
  for (final entry in entries) {
    final local = entry.loggedAt.toLocal();
    final day = '${local.year}-${local.month}-${local.day}';
    if (day != lastDay) {
      rows.add(_DayHeader(_formatDay(local)));
      lastDay = day;
    }
    rows.add(_EntryRow(entry));
  }
  return rows;
}

String _formatDay(DateTime d) {
  final now = DateTime.now();
  final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
  if (isToday) return 'Today';

  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
  if (isYesterday) return 'Yesterday';

  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
```

- [ ] **Step 8: Verify the whole suite**

Run: `fvm flutter test && fvm flutter analyze && fvm dart format --set-exit-if-changed .`
Expected: every suite passes, analyze clean, formatting already correct. If
format rewrites files, commit the result.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Show the shop's scan log, a day at a time"
```

---

### Task 11: Sign out when the token expires

**Files:**
- Modify: `lib/auth/auth_notifier.dart` (add `handleApiError`),
  `lib/scan/scan_notifier.dart` (three catch sites),
  `lib/logs/logs_notifier.dart` (two catch sites)
- Test: `test/scan/scan_notifier_test.dart`, `test/logs/logs_notifier_test.dart`
  (additions)

**Interfaces:**
- Consumes: `ApiException`, `ApiErrorKind`, `authProvider`.
- Produces: on `AuthNotifier` — `void handleApiError(ApiException e)`.

**Why this is its own task.** The token lasts seven days and there is no refresh
endpoint, so expiry is not an edge case — it happens to every device, weekly,
usually mid-shift. Tasks 6 and 8-10 catch `ApiException` and render the message
where the failure happened, which for a 401 means a staff member reading "Your
session has expired. Please sign in again." on the scan screen with no way to
do it. The router already sends `AuthSignedOut` to `/login`; nothing was
triggering it.

- [ ] **Step 1: Write the failing tests**

Append to `test/scan/scan_notifier_test.dart`, inside `main()`. It needs the
auth providers in the container, so add this variant next to `containerWith()`:

```dart
  test('a 401 during a lookup signs the user out', () async {
    api = FakeApiClient();
    final store = FakeTokenStore();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    await container.read(authProvider.notifier).restore();
    api.cardError = ApiException(
      ApiErrorKind.unauthorized,
      'Your session has expired. Please sign in again.',
    );

    await container.read(scanProvider.notifier).lookUp('ABC1234567');

    expect(container.read(authProvider), isA<AuthSignedOut>());
    expect(store.clearCount, 1);
  });

  test('a 400 does not sign anyone out', () async {
    // Only an expired token ends the session. A refused action is not a reason
    // to make someone sign in again mid-transaction.
    api = FakeApiClient();
    final store = FakeTokenStore();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    await container.read(authProvider.notifier).restore();
    api.card = rewardCard();
    await container.read(scanProvider.notifier).lookUp('ABC1234567');
    api.actionError =
        ApiException(ApiErrorKind.badRequest, 'Stamps not yet complete (3/10)');

    await container.read(scanProvider.notifier).addToRewards();

    expect(container.read(authProvider), isA<AuthSignedIn>());
    expect(store.clearCount, 0);
  });
```

Add these imports to that file:

```dart
import 'package:qwallet_scan/auth/token_store.dart';
```

And append to `test/logs/logs_notifier_test.dart`, inside `main()`:

```dart
  test('a 401 loading the log signs the user out', () async {
    api = FakeApiClient();
    final store = FakeTokenStore();
    store.stored = const StoredAuth(
      token: 'jwt',
      name: 'Sam',
      role: 'staff',
      businessIds: ['biz-1'],
      businessId: 'biz-1',
    );
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    await container.read(authProvider.notifier).restore();
    api.logError = ApiException(
      ApiErrorKind.unauthorized,
      'Your session has expired. Please sign in again.',
    );

    await container.read(logsProvider.notifier).loadFirstPage();

    expect(container.read(authProvider), isA<AuthSignedOut>());
  });
```

with the import:

```dart
import 'package:qwallet_scan/auth/token_store.dart';
```

Note these three tests do **not** override `businessIdProvider`: they need the
real one, derived from the restored session, so that signing out genuinely
changes what it returns.

- [ ] **Step 2: Run to watch them fail**

Run: `fvm flutter test test/scan/scan_notifier_test.dart test/logs/logs_notifier_test.dart`
Expected: FAIL on the two 401 tests — auth stays `AuthSignedIn` because nothing
signs out. The 400 test passes already; it is there to stay passing.

- [ ] **Step 3: Add `handleApiError` to `AuthNotifier`**

In `lib/auth/auth_notifier.dart`, inside `AuthNotifier`:

```dart
  /// The one place an expired session is acted on.
  ///
  /// The token lasts seven days and there is no refresh endpoint, so every
  /// device hits this eventually. Signing out flips `authProvider`, which the
  /// router is listening to, so the staff member lands on the login screen with
  /// the reason showing — rather than reading "your session has expired" on a
  /// screen that offers no way to fix it.
  ///
  /// Deliberately only 401. A 403 means this business is not theirs, which is a
  /// different problem, and a 400 is a refused action mid-transaction — neither
  /// is a reason to throw away a working session.
  void handleApiError(ApiException e) {
    if (e.kind == ApiErrorKind.unauthorized) {
      signOut(reason: e.message);
    }
  }
```

- [ ] **Step 4: Call it from every catch site**

In `lib/scan/scan_notifier.dart`, each of the three
`on ApiException catch (e) {` blocks gains one line as its first statement:

```dart
    } on ApiException catch (e) {
      ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFailed(e.message);          // in lookUp
    }
```

```dart
    } on ApiException catch (e) {
      ref.read(authProvider.notifier).handleApiError(e);
      state = ScanFound(current.card, actionError: e.message);   // in _act,
    }                                          // adjustPoints, renewMembership
```

In `lib/logs/logs_notifier.dart`, both catch blocks:

```dart
    } on ApiException catch (e) {
      ref.read(authProvider.notifier).handleApiError(e);
      state = LogsState(error: e.message);      // in loadFirstPage
    }
```

```dart
    } on ApiException catch (e) {
      ref.read(authProvider.notifier).handleApiError(e);
      state = current.copyWith(loadingMore: false, error: e.message);  // loadMore
    }
```

The state is still set after signing out. It is never seen — the router replaces
the screen — but leaving the notifier in a coherent state costs nothing and
means these methods do not behave differently depending on who called them.

- [ ] **Step 5: Verify**

Run: `fvm flutter test && fvm flutter analyze`
Expected: every suite passes, including the three new tests; analyze clean.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Send an expired session back to the login screen"
```

---

## Notes for whoever runs this

**Point it at a real API before believing anything.** All ten tasks run against
fakes. The first run against the live server needs:

```bash
fvm flutter run --dart-define=API_BASE_URL=https://api.qwallet.me
```

and a staff account that is actually linked to a business.

**Migrations 011, 012 and 013 must be applied to whatever API this talks to.**
They are merged on `loyalty-pass-api` `main` and, as of 2026-09-07, had not been
run against production. Until they are, `GET /api/passes/:cardId` is fine but
template saves in the dashboard fail — which is a different symptom from
anything this app does, and worth knowing before chasing it here.

**The scan log will not show points or membership activity.** Only `/stamp`
writes `scan_log` and only `/redeem` writes `redemption_log`. This is in the
spec's Known limitations and is not a bug in the app.
