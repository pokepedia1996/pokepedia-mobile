import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/auth_errors.dart';
import '../../../shared/widgets/auth_card.dart';

/// Ports `app/login/page.tsx`.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
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
    final error = await ref
        .read(authProvider.notifier)
        .signIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = translateAuthError(error);
      });
      return;
    }
    context.go(Routes.account);
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: 'Masuk ke pokepedia.id',
      subtitle: 'Selamat datang kembali, masuk untuk melanjutkan',
      formBody: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Password tidak boleh kosong' : null,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push(Routes.forgotPassword),
                child: const Text('Lupa password?'),
              ),
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTypography.bodySm(context.appColors.error),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
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
                  : const Text('Masuk'),
            ),
          ],
        ),
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
