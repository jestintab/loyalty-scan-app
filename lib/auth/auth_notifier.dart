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

  /// Shown on the login screen. Null on a first launch or a deliberate
  /// sign-out.
  final String? error;
}

class AuthNeedsBusiness extends AuthState {
  const AuthNeedsBusiness(this.auth);
  final StoredAuth auth;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.auth);

  /// `auth.businessId` is non-null in this state — that is what the state
  /// means.
  final StoredAuth auth;
}

const _rolesAllowed = {'admin', 'business', 'staff'};

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthLoading();

  TokenStore get _store => ref.read(tokenStoreProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  /// Called once at startup.
  ///
  /// The stored session is shown straight away — a till must open even with
  /// no signal — and then renewed in the background.
  Future<void> restore() async {
    final stored = await _store.read();
    if (stored == null) {
      state = const AuthSignedOut();
      return;
    }
    state = stored.businessId == null
        ? AuthNeedsBusiness(stored)
        : AuthSignedIn(stored);
    await renew(force: true);
  }

  /// How often a session is renewed at most, outside of a fresh launch.
  static const renewInterval = Duration(minutes: 30);

  DateTime? _lastRenewal;
  Future<void>? _renewing;

  /// Swaps the session for a fresh seven-day one.
  ///
  /// The token used to last exactly seven days from sign-in with no way to
  /// extend it, so every staff phone was sent to the login screen once a
  /// week. Called on launch, on returning to the foreground, and hourly while
  /// the app stays open, so any phone used within a week stays signed in.
  ///
  /// Only a 401 signs out — the session had already expired, or the account
  /// was switched off. Offline or a server error keeps the session as it is;
  /// the next launch or resume tries again.
  Future<void> renew({bool force = false}) {
    final inFlight = _renewing;
    if (inFlight != null) return inFlight;
    final last = _lastRenewal;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < renewInterval) {
      return Future.value();
    }
    final run = _renew();
    _renewing = run;
    return run.whenComplete(() => _renewing = null);
  }

  Future<void> _renew() async {
    final current = _currentAuth;
    if (current == null) return;
    try {
      final session = await _api.refreshSession(current.token);
      // Signed out, or signed in as someone else, while the call was out:
      // this answer belongs to a session that is gone.
      if (_currentAuth?.token != current.token) return;
      _lastRenewal = DateTime.now();

      if (!_rolesAllowed.contains(session.role)) {
        await signOut(reason: 'This app is for staff and business owners.');
        return;
      }
      if (session.businessIds.isEmpty) {
        await signOut(
          reason:
              'This account is not linked to a business. Ask the owner to add you.',
        );
        return;
      }

      // Re-read: a business may have been picked while the call was out.
      final latest = _currentAuth!;
      final chosen = latest.businessId;
      final businessId = chosen != null && session.businessIds.contains(chosen)
          ? chosen
          : session.businessIds.length == 1
          ? session.businessIds.first
          : null;
      final updated = StoredAuth(
        token: session.token,
        name: session.name,
        role: session.role,
        businessIds: session.businessIds,
        businessId: businessId,
      );
      await _store.write(updated);
      state = businessId == null
          ? AuthNeedsBusiness(updated)
          : AuthSignedIn(updated);
    } on ApiException catch (e) {
      if (_currentAuth?.token != current.token) return;
      await handleApiError(e);
    }
  }

  StoredAuth? get _currentAuth => switch (state) {
    AuthNeedsBusiness(:final auth) => auth,
    AuthSignedIn(:final auth) => auth,
    _ => null,
  };

  Future<void> signIn(String identifier, String password) async {
    state = const AuthLoading();
    try {
      final session = await _api.login(
        identifier: identifier,
        password: password,
      );

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
          error:
              'This account is not linked to a business. Ask the owner to add you.',
        );
        return;
      }

      final single = session.businessIds.length == 1
          ? session.businessIds.first
          : null;
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
      // A 401 on the sign-in call itself is a wrong password, not a stale
      // token, and the generic wording sends people in a circle: they are told
      // their session expired and to sign in again, which is what they were
      // doing. Only this call can tell the two apart, so it supplies the copy.
      state = AuthSignedOut(
        error: e.kind == ApiErrorKind.unauthorized
            ? "We couldn't sign you in. Check the email or mobile number and "
                  'password.'
            : e.message,
      );
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

  /// The one place an expired session is acted on.
  ///
  /// The token lasts seven days. `renew()` keeps extending it while the app is
  /// in use, so this is reached by a phone left unused for a week, or an
  /// account that was switched off. Signing out flips `authProvider`, which the
  /// router is listening to, so the staff member lands on the login screen with
  /// the reason showing — rather than reading "your session has expired" on a
  /// screen that offers no way to fix it.
  ///
  /// Deliberately only 401. A 403 means this business is not theirs, which is a
  /// different problem, and a 400 is a refused action mid-transaction — neither
  /// is a reason to throw away a working session.
  /// Returns a Future so callers can await the sign-out before reporting their
  /// own work finished — signOut clears the keychain, and a caller that does
  /// not wait can settle while the token is still on disk.
  Future<void> handleApiError(ApiException e) async {
    if (e.kind == ApiErrorKind.unauthorized) {
      await signOut(reason: e.message);
    }
  }

  /// The token for the HTTP layer, or null when signed out.
  String? get token => switch (state) {
    AuthNeedsBusiness(:final auth) => auth.token,
    AuthSignedIn(:final auth) => auth.token,
    _ => null,
  };
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// The business every API call needs, or null when there isn't one yet.
final businessIdProvider = Provider<String?>((ref) {
  final state = ref.watch(authProvider);
  return state is AuthSignedIn ? state.auth.businessId : null;
});
