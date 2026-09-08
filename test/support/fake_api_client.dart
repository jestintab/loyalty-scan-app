import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';
import 'package:qwallet_scan/api/models/loyalty_card.dart';
import 'package:qwallet_scan/api/models/scan_log_entry.dart';
import 'package:qwallet_scan/api/models/session.dart';
import 'package:qwallet_scan/auth/token_store.dart';

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
  Future<Session> login({
    required String identifier,
    required String password,
  }) async {
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
    // An empty queue answers with an empty page rather than throwing: every
    // finished action now refreshes the dashboard, so tests about a button
    // would otherwise have to prime a scan log they say nothing about.
    if (logPages.isEmpty) {
      return const ScanLogPage(entries: [], hasMore: false, nextCursor: null);
    }
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
