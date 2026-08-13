import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Ports `app/settings/page.tsx` — `components/seller/settings-client.tsx`'s
/// buyer-facing counterpart (profile fields + notification toggles).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _username;
  late final TextEditingController _email;
  final _phone = TextEditingController(text: '0812-3456-7890');
  bool _emailNotif = true;
  bool _pushNotif = true;
  bool _marketingNotif = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    _username = TextEditingController(text: user?.username ?? '');
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Profil',
              children: [
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Nomor HP'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Notifikasi',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Email',
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                  value: _emailNotif,
                  onChanged: (v) => setState(() => _emailNotif = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Push notification',
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                  value: _pushNotif,
                  onChanged: (v) => setState(() => _pushNotif = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Promo & info terbaru',
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                  value: _marketingNotif,
                  onChanged: (v) => setState(() => _marketingNotif = v),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pengaturan disimpan')),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.bodySmSemibold(context.appColors.onSurface),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
