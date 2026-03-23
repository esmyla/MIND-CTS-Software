/// lib/features/auth/presentation/login_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_provider.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _isSignUp = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final notifier = ref.read(sessionProvider.notifier);
    final AuthResult result;

    if (_isSignUp) {
      result = await notifier.signUp(_emailCtrl.text, _passCtrl.text);
    } else {
      result = await notifier.signIn(_emailCtrl.text, _passCtrl.text);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (result is AuthFailure) {
      setState(() => _errorMsg = result.message);
    }
  }

  void _skip() => ref.read(sessionProvider.notifier).continueAsGuest();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----------------------------------------------------------
                  // Logo / branding
                  // ----------------------------------------------------------
                  Icon(
                    Icons.accessibility_new_rounded,
                    size: 72,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'MIND CTS',
                    style: tt.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Physical Therapy Companion',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // ----------------------------------------------------------
                  // Auth disabled banner
                  // ----------------------------------------------------------
                  if (session.authBannerVisible) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: cs.onTertiaryContainer,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Auth disabled in this build — '
                              'using guest mode.',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ----------------------------------------------------------
                  // Toggle Sign In / Sign Up
                  // ----------------------------------------------------------
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign In')),
                      ButtonSegment(value: true, label: Text('Create Account')),
                    ],
                    selected: {_isSignUp},
                    onSelectionChanged: (s) =>
                        setState(() => _isSignUp = s.first),
                  ),

                  const SizedBox(height: 24),

                  // ----------------------------------------------------------
                  // Form
                  // ----------------------------------------------------------
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  // Error message
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMsg!,
                      style: tt.bodySmall?.copyWith(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ----------------------------------------------------------
                  // Primary action button
                  // ----------------------------------------------------------
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),

                  const SizedBox(height: 16),

                  // ----------------------------------------------------------
                  // Skip / guest mode
                  // ----------------------------------------------------------
                  OutlinedButton(
                    onPressed: _loading ? null : _skip,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Skip — Continue as Guest'),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Guest mode lets you use all features locally.\n'
                    'Sign in to sync your progress across devices.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.55),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
