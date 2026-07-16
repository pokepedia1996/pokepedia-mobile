import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/auth_card.dart';

/// Ports `app/forgot-password/page.tsx`.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: 'Lupa password?',
      subtitle: 'Masukkan email untuk menerima tautan reset password',
      formBody: _sent
          ? Column(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 40,
                  color: context.appSemantic.success,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tautan reset password telah dikirim ke ${_email.text}.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Email tidak valid'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() => _sent = true);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Kirim tautan reset'),
                  ),
                ],
              ),
            ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Ingat password? ',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          GestureDetector(
            onTap: () => context.go(Routes.login),
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
