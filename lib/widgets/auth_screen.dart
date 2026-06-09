import 'dart:async';

import 'package:flutter/material.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onContinueInLocalTestMode;

  const AuthScreen({
    super.key,
    required this.authService,
    this.onContinueInLocalTestMode,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;
  bool _showEmailForm = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    unawaited(
      AnalyticsService.track(
        'sign_in_attempted',
        properties: {'method': 'google'},
      ),
    );
    final success = await widget.authService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      unawaited(
        AnalyticsService.track(
          'sign_in_failed',
          properties: {'method': 'google'},
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.authService.lastError ?? 'Google sign in failed.',
            ),
          ),
        );
      }
    } else {
      unawaited(
        AnalyticsService.track(
          'sign_in_succeeded',
          properties: {'method': 'google'},
        ),
      );
    }
  }

  Future<void> _signInWithEmail() async {
    setState(() => _isLoading = true);
    final email = _emailController.text;
    final password = _passwordController.text;
    unawaited(
      AnalyticsService.track(
        'sign_in_attempted',
        properties: {'method': 'email'},
      ),
    );
    final success = await widget.authService.signInWithEmail(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success && mounted) {
      unawaited(
        AnalyticsService.track(
          'sign_in_failed',
          properties: {'method': 'email'},
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.authService.lastError ?? 'Email sign in failed.',
          ),
        ),
      );
    } else if (success) {
      unawaited(
        AnalyticsService.track(
          'sign_in_succeeded',
          properties: {'method': 'email'},
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome to Navi',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your personal mood and insight companion',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                if (widget.authService.supportsGoogleSignIn) ...[
                  ElevatedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _showEmailForm = !_showEmailForm;
                    });
                    unawaited(
                      AnalyticsService.track(
                        'email_sign_in_form_toggled',
                        properties: {'shown': _showEmailForm},
                      ),
                    );
                  },
                  child: Text(
                    _showEmailForm
                        ? 'Hide email sign in'
                        : 'Sign in with email',
                  ),
                ),
                if (_showEmailForm) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _signInWithEmail,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Sign in'),
                  ),
                ],
                if (!widget.authService.supportsGoogleSignIn) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Google sign-in is unavailable on this platform. Use email and password to sign in for verification.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (widget.onContinueInLocalTestMode != null) ...[
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: widget.onContinueInLocalTestMode,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Continue in local test mode'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
