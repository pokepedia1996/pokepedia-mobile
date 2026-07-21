import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Ports `components/account/account-list.tsx` — the Akun tab.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final isGuest = user == null;
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.secondary,
                    child: Icon(
                      isGuest ? Icons.person_add_alt : Icons.person,
                      color: context.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? 'Tamu' : (user.username ?? user.email),
                          style: AppTypography.bodySemibold(colors.onSurface),
                        ),
                        GestureDetector(
                          onTap: (isGuest || user.username == null)
                              ? null
                              : () => context.push(Routes.userProfile(user.username!)),
                          child: Text(
                            isGuest
                                ? 'Masuk untuk koleksi & marketplace'
                                : 'Lihat profil',
                            style: AppTypography.caption(context.mutedForeground),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isGuest)
                    ElevatedButton(
                      onPressed: () => context.push(Routes.login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.appSemantic.success,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Masuk'),
                    ),
                ],
              ),
            ),
            if (!isGuest)
              _Group(
                title: 'Portofolio',
                children: [
                  _Row(
                    icon: Icons.checklist,
                    label: 'List',
                    onTap: () => context.push(Routes.lists),
                  ),
                  _Row(
                    icon: Icons.grid_view_rounded,
                    label: 'Deck',
                    onTap: () => context.push(Routes.portfolio),
                  ),
                  _Row(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventori',
                    onTap: () => context.push(Routes.portfolio),
                  ),
                ],
              ),
            _Group(
              title: 'Aktivitas',
              children: isGuest
                  ? [
                      _Row(
                        icon: Icons.people_outline,
                        label: 'Cari Pengguna',
                        onTap: () => context.push(Routes.users),
                      ),
                    ]
                  : [
                      _Row(
                        icon: Icons.inventory_2_outlined,
                        label: 'Pesanan',
                        onTap: () => context.push(Routes.orders),
                      ),
                      _Row(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Keranjang',
                        onTap: () => context.push(Routes.cart),
                      ),
                      _Row(
                        icon: Icons.notifications_none,
                        label: 'Notifikasi',
                        onTap: () => context.push(Routes.notifications),
                      ),
                      _Row(
                        icon: Icons.chat_bubble_outline,
                        label: 'Pesan',
                        onTap: () => context.push(Routes.chat),
                      ),
                      _Row(
                        icon: Icons.checklist,
                        label: 'Proposal Saya',
                        onTap: () => context.push(Routes.proposals),
                      ),
                      _Row(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Saldo',
                        onTap: () => context.push(Routes.wallet),
                      ),
                      _Row(
                        icon: Icons.people_outline,
                        label: 'Cari Pengguna',
                        onTap: () => context.push(Routes.users),
                      ),
                      _Row(
                        icon: Icons.storefront_outlined,
                        label: 'Dashboard Penjual',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dashboard Penjual belum tersedia di pass ini'),
                          ),
                        ),
                      ),
                    ],
            ),
            _Group(
              title: 'Informasi',
              children: [
                _Row(
                  icon: Icons.menu_book_outlined,
                  label: 'Tutorial',
                  onTap: () => context.push(Routes.tutorial),
                ),
                _Row(
                  icon: Icons.help_outline,
                  label: 'Bantuan',
                  onTap: () => context.push(Routes.support),
                ),
                _Row(
                  icon: Icons.description_outlined,
                  label: 'Syarat & Ketentuan',
                  onTap: () => context.push(Routes.terms('syarat-dan-ketentuan')),
                ),
                _Row(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Kebijakan Privasi',
                  onTap: () => context.push(Routes.terms('kebijakan-privasi')),
                ),
                _Row(
                  icon: Icons.description_outlined,
                  label: 'Panduan Kondisi Kartu',
                  onTap: () => context.push(Routes.terms('kondisi-kartu')),
                ),
              ],
            ),
            Consumer(
              builder: (context, ref, _) {
                final mode = ref.watch(themeModeProvider);
                final hint = switch (mode) {
                  ThemeMode.system => 'Otomatis',
                  ThemeMode.dark => 'Gelap',
                  ThemeMode.light => 'Terang',
                };
                final icon = switch (mode) {
                  ThemeMode.system => Icons.brightness_auto,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                };
                return _Group(
                  title: 'Pengaturan',
                  children: [
                    _Row(
                      icon: icon,
                      label: 'Tampilan',
                      hint: hint,
                      onTap: () => ref.read(themeModeProvider.notifier).cycle(),
                    ),
                    if (!isGuest)
                      _Row(
                        icon: Icons.settings_outlined,
                        label: 'Pengaturan akun',
                        onTap: () => context.push(Routes.settings),
                      ),
                    if (isGuest)
                      _Row(
                        icon: Icons.login,
                        label: 'Masuk / Daftar',
                        onTap: () => context.push(Routes.login),
                      )
                    else
                      _Row(
                        icon: Icons.logout,
                        label: 'Keluar',
                        destructive: true,
                        onTap: () => _confirmLogout(context, ref),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Keluar dari akun?'),
        content: const Text('Kamu yakin ingin keluar dari pokepedia.id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
            ),
            onPressed: () {
              ref.read(authProvider.notifier).signOut();
              Navigator.of(context).pop();
            },
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              title.toUpperCase(),
              style: AppTypography.overline(context.mutedForeground),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.symmetric(
                horizontal: BorderSide(color: context.borderColor),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: context.borderColor),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? hint;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fg = destructive ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: destructive ? colors.error : context.mutedForeground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppTypography.bodySmSemibold(fg)),
            ),
            if (hint != null)
              Text(hint!, style: AppTypography.caption(context.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
