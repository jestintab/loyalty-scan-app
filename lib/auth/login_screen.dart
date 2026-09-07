import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/brand_logo.dart';
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
                    // The mark, not a typed-out name: this is the first screen
                    // a new staff member sees and it should say whose app it is
                    // the way the counter signage does.
                    const BrandLogo(height: 52),
                    const SizedBox(height: 18),
                    Text(
                      'Scan',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to stamp and redeem cards.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
