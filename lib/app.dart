import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_notifier.dart';
import 'ui/theme.dart';
import 'router.dart';

class QwalletScanApp extends ConsumerStatefulWidget {
  const QwalletScanApp({super.key});

  @override
  ConsumerState<QwalletScanApp> createState() => _QwalletScanAppState();
}

class _QwalletScanAppState extends ConsumerState<QwalletScanApp>
    with WidgetsBindingObserver {
  Timer? _renewTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: restore() writes to a provider, which cannot
    // happen during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).restore();
    });
    // A till phone can sit on the scan screen for days without ever going to
    // the background, so resuming alone would not keep its session alive.
    _renewTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => ref.read(authProvider.notifier).renew(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).renew();
    }
  }

  @override
  void dispose() {
    _renewTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider) is AuthLoading) {
      return MaterialApp(
        theme: qwalletLight,
        darkTheme: qwalletDark,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: 'Qwallet Scanner',
      theme: qwalletLight,
      // A staff phone is on whatever the person set it to, and a till app that
      // blazes white through a late shift is the one they turn the brightness
      // down for — which is also when the scan screen stops being readable.
      darkTheme: qwalletDark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
