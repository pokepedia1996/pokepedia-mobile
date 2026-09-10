import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/auth_errors.dart';
import '../../../shared/widgets/auth_card.dart';
import 'widgets/google_sign_in_button.dart';

/// Ports `app/signup/page.tsx`.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  String? _error;
  bool _needsEmailConfirmation = false;

  /// Any of the three ways in is running, so the other two are held.
  bool get _busy => _submitting || _googleLoading || _appleLoading;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(authProvider.notifier)
        .signUp(_username.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    switch (result.outcome) {
      case SignUpOutcome.signedIn:
        context.go(Routes.account);
      case SignUpOutcome.needsEmailConfirmation:
        setState(() {
          _submitting = false;
          _needsEmailConfirmation = true;
        });
      case SignUpOutcome.error:
        setState(() {
          _submitting = false;
          _error = translateAuthError(result.errorMessage ?? '');
        });
    }
  }

  /// Registering with Google is the same call as signing in with it: the
  /// first time an account uses the provider, Supabase creates the user. So
  /// there is no separate "sign up" path to write — only the label differs,
  /// which is what [SocialButtonsMode] carries.
  ///
  /// No email confirmation step either: Google has already verified the
  /// address, so the session exists by the time this returns.
  Future<void> _google() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    final result = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;

    setState(() {
      _googleLoading = false;
      if (result.error != null) {
        _error = translateAuthError(result.error!, provider: 'Google');
      }
    });

    // Backing out of the account sheet returns with neither flag set, which
    // deliberately does nothing.
    if (result.signedIn && mounted) context.go(Routes.account);
  }

  /// Same shape as [_google]: Apple creates the account on first use, so
  /// registering and signing in are one call.
  Future<void> _apple() async {
    setState(() {
      _appleLoading = true;
      _error = null;
    });
    final result = await ref.read(authProvider.notifier).signInWithApple();
    if (!mounted) return;

    setState(() {
      _appleLoading = false;
      if (result.error != null) {
        _error = translateAuthError(result.error!, provider: 'Apple');
      }
    });

    if (result.signedIn && mounted) context.go(Routes.account);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsEmailConfirmation) {
      return AuthCard(
        title: 'Cek email kamu',
        subtitle: 'Klik tautan di email untuk mengaktifkan akunmu',
        formBody: Column(
          children: [
            Icon(
              LucideIcons.mailCheck,
              size: 40,
              color: context.appSemantic.success,
            ),
            const SizedBox(height: 12),
            Text(
              'Kami telah mengirim tautan aktivasi ke ${_email.text}.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
        ),
        footer: Center(
          child: TextButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Kembali ke halaman masuk'),
          ),
        ),
      );
    }

    return AuthCard(
      title: 'Buat akun pokepedia.id',
      subtitle: 'Gratis untuk jual beli & mengelola koleksimu',
      formBody: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Username wajib diisi'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Email tidak valid' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Minimal 8 karakter' : null,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTypography.bodySm(context.appColors.error),
              ),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              // Also held while Google is in flight, so the two ways of
              // registering can't be started at once.
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Daftar'),
            ),
            SocialButtons(
              mode: SocialButtonsMode.signup,
              loading: _googleLoading,
              appleLoading: _appleLoading,
              onGooglePressed: _busy ? null : _google,
              onApplePressed: _busy ? null : _apple,
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sudah punya akun? ',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          GestureDetector(
            onTap: () => context.push(Routes.login),
            child: Text(
              'Masuk',
              style: AppTypography.bodySmSemibold(context.appColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
