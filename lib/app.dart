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
