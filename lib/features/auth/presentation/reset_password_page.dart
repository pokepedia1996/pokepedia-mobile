import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auth_card.dart';

/// Ports `app/reset-password/page.tsx`.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
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
            ElevatedButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password berhasil diubah')),
                );
                context.go(Routes.login);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Simpan password baru'),
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
