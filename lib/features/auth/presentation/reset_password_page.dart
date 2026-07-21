import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/auth_errors.dart';
import '../../../shared/widgets/auth_card.dart';

/// Ports `app/reset-password/page.tsx`. Relies on the recovery email link
/// having already established a session (via the deep link →
/// `verifyOtp`/`exchangeCodeForSession` handling supabase_flutter does
/// internally) before landing here — without one there's nothing to reset.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasSession = ref.read(supabaseClientProvider).auth.currentSession != null;
      if (!hasSession) context.go(Routes.login);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await ref.read(authProvider.notifier).updatePassword(_password.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = translateAuthError(error);
      });
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Password berhasil diubah')));
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: 'Atur ulang password',
      subtitle: 'Masukkan password baru untuk akunmu',
      formBody: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password baru'),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Minimal 8 karakter' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Konfirmasi password',
              ),
              validator: (v) =>
                  v != _password.text ? 'Password tidak sama' : null,
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
                  : const Text('Simpan password baru'),
            ),
          ],
        ),
      ),
      footer: Center(
        child: TextButton(
          onPressed: () => context.go(Routes.login),
          child: Text(
            'Kembali ke halaman masuk',
            style: TextStyle(color: context.mutedForeground),
          ),
        ),
      ),
    );
  }
}
