import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/auth_errors.dart';
import '../../../shared/widgets/auth_card.dart';
import 'widgets/google_sign_in_button.dart';

/// Ports `app/login/page.tsx`, including its two-step shape: the email is
/// asked for first, then the password on its own screen. Google sits under
/// the first step, where someone who never set a password belongs.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _Step { email, password }

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  _Step _step = _Step.email;
  bool _obscure = true;
  bool _submitting = false;
  bool _googleLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Ports `validateEmail`.
  String? _validateEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Email tidak boleh kosong';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Email tidak valid';
    }
    return null;
  }

  /// Ports `handleContinue` — advances to the password step.
  void _continue() {
    final error = _validateEmail(_email.text);
    if (error != null) {
      setState(() => _emailError = error);
      return;
    }
    setState(() {
      _emailError = null;
      _generalError = null;
      _step = _Step.password;
    });
    // The password field is the only thing on the next step; focus it so the
    // keyboard doesn't have to be summoned again.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _passwordFocus.requestFocus(),
    );
  }

  void _back() {
    setState(() {
      _passwordError = null;
      _generalError = null;
      _step = _Step.email;
    });
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _passwordError = 'Password tidak boleh kosong');
      return;
    }
    setState(() {
      _submitting = true;
      _passwordError = null;
      _generalError = null;
    });

    final error = await ref
        .read(authProvider.notifier)
        .signIn(_email.text.trim(), _password.text);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _generalError = translateAuthError(error);
      });
      return;
    }
    context.go(Routes.account);
  }

  Future<void> _google() async {
    setState(() {
      _googleLoading = true;
      _generalError = null;
    });
    final result = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;

    setState(() {
      _googleLoading = false;
      if (result.error != null) {
        _generalError = translateAuthError(result.error!);
      }
    });

    // The native sheet establishes the session before returning, so unlike
    // the old browser hand-off there is somewhere to go immediately.
    // Backing out of the sheet lands here with neither flag set, and that
    // deliberately does nothing.
    if (result.signedIn && mounted) context.go(Routes.account);
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: 'Masuk ke pokepedia.id',
      subtitle: 'Selamat datang kembali, masuk untuk melanjutkan',
      formBody: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_generalError != null) ...[
            _ErrorAlert(message: _generalError!),
            const SizedBox(height: 16),
          ],
          // A cross-fade rather than a swap, so the card doesn't jump as the
          // two steps differ in height.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _step == _Step.email
                ? _EmailStep(
                    controller: _email,
                    error: _emailError,
                    googleLoading: _googleLoading,
                    onChanged: () {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    onContinue: _continue,
                    onGoogle: _google,
                  )
                : _PasswordStep(
                    email: _email.text.trim(),
                    controller: _password,
                    focusNode: _passwordFocus,
                    error: _passwordError,
                    obscure: _obscure,
                    submitting: _submitting,
                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                    onChanged: () {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                    onBack: _back,
                    onSubmit: _submit,
                  ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Belum punya akun? ',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          GestureDetector(
            onTap: () => context.push(Routes.signup),
            child: Text(
              'Daftar',
              style: AppTypography.bodySmSemibold(context.appColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.controller,
    required this.error,
    required this.googleLoading,
    required this.onChanged,
    required this.onContinue,
    required this.onGoogle,
  });

  final TextEditingController controller;
  final String? error;
  final bool googleLoading;
  final VoidCallback onChanged;
  final VoidCallback onContinue;
  final VoidCallback onGoogle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          autofocus: true,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onContinue(),
          decoration: InputDecoration(labelText: 'Email', errorText: error),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Lanjutkan'),
        ),
        SocialButtons(onGooglePressed: onGoogle, loading: googleLoading),
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.email,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.obscure,
    required this.submitting,
    required this.onToggleObscure,
    required this.onChanged,
    required this.onBack,
    required this.onSubmit,
  });

  final String email;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final bool obscure;
  final bool submitting;
  final VoidCallback onToggleObscure;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 14, color: context.mutedForeground),
              const SizedBox(width: 6),
              Text(
                'Kembali',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // The email chip: tapping it goes back to change it, as on the web.
        GestureDetector(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit, size: 12, color: context.mutedForeground),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          autofillHints: const [AutofillHints.password],
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: error,
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => context.push(Routes.forgotPassword),
          child: Text(
            'Lupa password?',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: submitting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text('Memproses...'),
                    ],
                  )
                : const Text('Masuk'),
          ),
        ),
      ],
    );
  }
}

/// Ports `components/ui/error-alert.tsx`.
class _ErrorAlert extends StatelessWidget {
  const _ErrorAlert({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: AppTypography.bodySm(colors.error)),
          ),
        ],
      ),
    );
  }
}
