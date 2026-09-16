import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/auth_errors.dart';
import '../../../shared/widgets/auth_card.dart';
import '../../../shared/widgets/auth_error_alert.dart';
import 'widgets/google_sign_in_button.dart';

/// Ports `app/signup/page.tsx`, including its three-step shape: the email is
/// asked for first, then the password on its own screen, then a confirmation
/// screen telling the user to go and open the link. The same two-step shape
/// `LoginPage` already had — this page used to ask for everything at once.
///
/// No username is collected, as on the web: `handle_new_user` writes the
/// profile row with a null one and it is chosen later, from Settings.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

enum _Step { email, password, success }

class _SignupPageState extends ConsumerState<SignupPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  _Step _step = _Step.email;
  bool _obscure = true;
  bool _submitting = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  /// Any of the three ways in is running, so the other two are held.
  bool get _busy => _submitting || _googleLoading || _appleLoading;

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
      return 'Masukkan alamat email yang valid';
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
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _passwordError = 'Password tidak boleh kosong');
      return;
    }
    if (password.length < 8) {
      setState(() => _passwordError = 'Password minimal 8 karakter');
      return;
    }

    setState(() {
      _submitting = true;
      _passwordError = null;
      _generalError = null;
    });

    final result = await ref
        .read(authProvider.notifier)
        .signUp(_email.text.trim(), password);
    if (!mounted) return;

    switch (result.outcome) {
      // Only reachable where email confirmation is turned off: the session
      // already exists, so there is nothing to go and confirm.
      case SignUpOutcome.signedIn:
        context.go(Routes.account);
      case SignUpOutcome.needsEmailConfirmation:
        setState(() {
          _submitting = false;
          _step = _Step.success;
        });
      case SignUpOutcome.error:
        setState(() {
          _submitting = false;
          _generalError = translateAuthError(result.errorMessage ?? '');
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
      _generalError = null;
    });
    final result = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;

    setState(() {
      _googleLoading = false;
      if (result.error != null) {
        _generalError = translateAuthError(result.error!, provider: 'Google');
      }
    });

    // Backing out of the account sheet returns with neither flag set, which
    // deliberately does nothing.
    if (result.signedIn && mounted) context.go(Routes.account);
  }

  /// Same shape as [_google]: Apple creates the account on first use, so
  /// registering and signing in are one call.
  ///
  /// Kept although the web page offers Google alone — App Store review
  /// expects an Apple option wherever other third-party sign-ins are shown.
  Future<void> _apple() async {
    setState(() {
      _appleLoading = true;
      _generalError = null;
    });
    final result = await ref.read(authProvider.notifier).signInWithApple();
    if (!mounted) return;

    setState(() {
      _appleLoading = false;
      if (result.error != null) {
        _generalError = translateAuthError(result.error!, provider: 'Apple');
      }
    });

    if (result.signedIn && mounted) context.go(Routes.account);
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _Step.success) {
      return _SuccessCard(email: _email.text.trim());
    }

    return AuthCard(
      title: 'Buat Akun',
      subtitle: 'Mulai koleksi kartu Pokemon kamu',
      formBody: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_generalError != null) ...[
            AuthErrorAlert(message: _generalError!),
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
                    appleLoading: _appleLoading,
                    busy: _busy,
                    onChanged: () {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    onContinue: _continue,
                    onGoogle: _google,
                    onApple: _apple,
                  )
                : _PasswordStep(
                    email: _email.text.trim(),
                    controller: _password,
                    focusNode: _passwordFocus,
                    error: _passwordError,
                    obscure: _obscure,
                    submitting: _submitting,
                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                    onChanged: () => setState(() {
                      if (_passwordError != null) _passwordError = null;
                    }),
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

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.controller,
    required this.error,
    required this.googleLoading,
    required this.appleLoading,
    required this.busy,
    required this.onChanged,
    required this.onContinue,
    required this.onGoogle,
    required this.onApple,
  });

  final TextEditingController controller;
  final String? error;
  final bool googleLoading;
  final bool appleLoading;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onContinue;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

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
          onPressed: busy ? null : onContinue,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Lanjutkan'),
        ),
        SocialButtons(
          mode: SocialButtonsMode.signup,
          loading: googleLoading,
          appleLoading: appleLoading,
          onGooglePressed: busy ? null : onGoogle,
          onApplePressed: busy ? null : onApple,
        ),
      ],
    );
  }
}

class _PasswordStep extends StatefulWidget {
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
  State<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<_PasswordStep> {
  /// Web disables "Daftar" until the password is long enough, so the rule is
  /// visible before the field is ever submitted. That needs the length as it
  /// is typed, which the parent doesn't otherwise track.
  bool get _longEnough => widget.controller.text.length >= 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canSubmit = !widget.submitting && _longEnough;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.arrowLeft,
                size: 14,
                color: context.mutedForeground,
              ),
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
          onTap: widget.onBack,
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
                    widget.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.pencil,
                  size: 12,
                  color: context.mutedForeground,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: widget.obscure,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) {
            setState(() {});
            widget.onChanged();
          },
          onSubmitted: (_) {
            if (canSubmit) widget.onSubmit();
          },
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: widget.error,
            // Web shows the rule as a hint under the field rather than
            // waiting for the submit to fail.
            helperText: widget.error == null ? 'Minimal 8 karakter' : null,
            suffixIcon: IconButton(
              icon: Icon(
                widget.obscure ? LucideIcons.eyeOff : LucideIcons.eye,
              ),
              onPressed: widget.onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canSubmit ? widget.onSubmit : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: widget.submitting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Memproses...'),
                    ],
                  )
                : const Text('Daftar'),
          ),
        ),
        const SizedBox(height: 12),
        const _TermsNotice(),
      ],
    );
  }
}

/// Ports the consent line under web's "Daftar" button. Both documents are
/// already native routes, so they open in the app rather than a browser tab.
///
/// Stateful only to own the tap recognizers: a [TextSpan] recognizer has to
/// be disposed by hand, and building them inline would leak one pair per
/// rebuild.
class _TermsNotice extends StatefulWidget {
  const _TermsNotice();

  @override
  State<_TermsNotice> createState() => _TermsNoticeState();
}

class _TermsNoticeState extends State<_TermsNotice> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()
      ..onTap = () => context.push(Routes.terms('syarat-dan-ketentuan'));
    _privacy = TapGestureRecognizer()
      ..onTap = () => context.push(Routes.terms('kebijakan-privasi'));
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = AppTypography.caption(context.appColors.primary);

    return Text.rich(
      TextSpan(
        style: AppTypography.caption(context.mutedForeground),
        children: [
          const TextSpan(text: 'Dengan mendaftar, kamu menyetujui '),
          TextSpan(
            text: 'Syarat & Ketentuan',
            style: link,
            recognizer: _terms,
          ),
          const TextSpan(text: ' dan '),
          TextSpan(
            text: 'Kebijakan Privasi',
            style: link,
            recognizer: _privacy,
          ),
          const TextSpan(text: ' kami.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Ports the `step === "success"` card — the address is repeated back so it
/// is obvious which inbox to open, and mistyping it is caught here rather
/// than by a confirmation link that never arrives.
class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AuthCard(
      title: 'Cek Email Kamu',
      formBody: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.mail, size: 28, color: colors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Kami telah mengirim link konfirmasi ke',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 12),
          Text(
            'Silakan cek email dan klik link untuk mengaktifkan akun.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ],
      ),
      footer: Center(
        child: GestureDetector(
          onTap: () => context.go(Routes.login),
          child: Text(
            'Kembali ke halaman login',
            style: AppTypography.bodySmSemibold(colors.primary),
          ),
        ),
      ),
    );
  }
}
