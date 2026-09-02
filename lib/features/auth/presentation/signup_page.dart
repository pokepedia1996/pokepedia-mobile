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
  String? _error;
  bool _needsEmailConfirmation = false;

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
              onPressed: _submitting ? null : _submit,
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
