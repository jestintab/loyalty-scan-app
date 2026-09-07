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
        // Nothing has been decided yet; hold wherever we are. app.dart shows a
        // splash until restore() completes.
        AuthLoading() => null,
        AuthSignedOut() => path == '/login' ? null : '/login',
        AuthNeedsBusiness() =>
          path == '/choose-business' ? null : '/choose-business',
        AuthSignedIn() =>
          (path == '/login' || path == '/choose-business') ? '/scan' : null,
      };
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/choose-business',
        builder: (_, _) => const BusinessPickerScreen(),
      ),
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
