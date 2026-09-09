import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/brand_logo.dart';
import 'auth_notifier.dart';
import 'country_codes.dart';
import 'phone_rules.dart';

/// Which of the two things a person is signing in with.
enum SignInWith { email, mobile }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  SignInWith _with = SignInWith.email;

  /// Qatar, because that is where the tills are. Anyone elsewhere changes it
  /// once and the number they type is validated against their own plan.
  String _dial = '+974';

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

    // E.164 for a mobile, which is the form accounts are stored in — the
    // picker exists so this can be built rather than typed.
    final identifier = _with == SignInWith.mobile
        ? toE164(_identifier.text, _dial)
        : _identifier.text.trim();

    try {
      await ref.read(authProvider.notifier).signIn(identifier, _password.text);
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
                    // Staff issued only a mobile number have no email to
                    // type, and the API matches on either — but one field
                    // taking both left the person to work out how, and a bare
                    // string of digits belongs to no country in particular.
                    SegmentedButton<SignInWith>(
                      segments: const [
                        ButtonSegment(
                          value: SignInWith.email,
                          label: Text('Email'),
                          icon: Icon(Icons.alternate_email),
                        ),
                        ButtonSegment(
                          value: SignInWith.mobile,
                          label: Text('Mobile'),
                          icon: Icon(Icons.phone_outlined),
                        ),
                      ],
                      selected: {_with},
                      onSelectionChanged: (selection) => setState(() {
                        _with = selection.first;
                        // What was typed belongs to the other field, and its
                        // complaint is about something no longer on screen.
                        _identifier.clear();
                        _formKey.currentState?.reset();
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_with == SignInWith.email)
                      TextFormField(
                        key: const Key('identifier'),
                        controller: _identifier,
                        autocorrect: false,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter your email'
                            : null,
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 128,
                            child: DropdownButtonFormField<String>(
                              key: const Key('dial'),
                              initialValue: _dial,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Country',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final c in countryCodes)
                                  DropdownMenuItem(
                                    value: c.dial,
                                    child: Text('${c.flag} ${c.dial}'),
                                  ),
                              ],
                              onChanged: (value) => setState(() {
                                if (value != null) _dial = value;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: const Key('identifier'),
                              controller: _identifier,
                              autocorrect: false,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Mobile number',
                                hintText: '3312 3456',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  switch (phoneProblem(v ?? '', _dial)) {
                                    PhoneProblem.empty =>
                                      'Enter your mobile number',
                                    PhoneProblem.invalid =>
                                      'Enter a valid mobile number',
                                    null => null,
                                  },
                            ),
                          ),
                        ],
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
