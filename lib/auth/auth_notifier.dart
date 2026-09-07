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
  Future<void> restore() async {
    final stored = await _store.read();
    if (stored == null) {
      state = const AuthSignedOut();
      return;
    }
    state =
        stored.businessId == null ? AuthNeedsBusiness(stored) : AuthSignedIn(stored);
  }

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

      final single =
          session.businessIds.length == 1 ? session.businessIds.first : null;
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
