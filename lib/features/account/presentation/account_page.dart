import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/user_avatar.dart';

/// Ports `app/account/account-list.tsx` — the Akun tab: the identity header
/// over grouped link rows (Portofolio, Aktivitas, Informasi, Pengaturan).
///
/// The web decorates Pesanan/Notifikasi/Pesan with unread count badges; the
/// app has no global unread counters yet, so those rows are plain.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);
    final user = authAsync.valueOrNull;
    final isGuest = user == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: SafeArea(
        top: false,
        child: authAsync.isLoading
            ? const _AccountSkeleton()
            : ListView(
                padding: EdgeInsets.only(
                  bottom: AppBottomNav.reservedSpace(context) + 12,
                ),
                children: [
                  _IdentityHeader(user: user),
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
                          onTap: () => context.push(Routes.decks),
                        ),
                        _Row(
                          icon: Icons.inventory_2_outlined,
                          label: 'Inventori',
                          onTap: () => context.push(Routes.inventory),
                        ),
                      ],
                    ),
                  if (!isGuest)
                    _Group(
                      title: 'Aktivitas',
                      children: [
                        _Row(
                          icon: Icons.inventory_2_outlined,
                          label: 'Pesanan',
                          onTap: () => context.push(Routes.orders),
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
                          icon: Icons.favorite_border,
                          label: 'Toko yang Diikuti',
                          onTap: () => context.push(Routes.accountFollowing),
                        ),
                        _Row(
                          icon: Icons.location_on_outlined,
                          label: 'Alamat',
                          onTap: () => context.push(Routes.addresses),
                        ),
                        _Row(
                          icon: Icons.people_outline,
                          label: 'Cari Pengguna',
                          onTap: () => context.push(Routes.users),
                        ),
                        _Row(
                          icon: Icons.storefront_outlined,
                          label: 'Dashboard Penjual',
                          onTap: () => context.push(Routes.seller),
                        ),
                        if (user.username != null)
                          _Row(
                            icon: Icons.shopping_bag_outlined,
                            label: 'Lihat Toko',
                            onTap: () => context.push(
                              Routes.storeDetail(user.username!),
                            ),
                          ),
                      ],
                    )
                  else
                    _Group(
                      children: [
                        _Row(
                          icon: Icons.people_outline,
                          label: 'Cari Pengguna',
                          onTap: () => context.push(Routes.users),
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
                        icon: Icons.favorite_border,
                        label: 'Dukung Pengembang',
                        onTap: () => context.push(Routes.support),
                      ),
                      _Row(
                        icon: Icons.description_outlined,
                        label: 'Syarat & Ketentuan',
                        onTap: () =>
                            context.push(Routes.terms('syarat-dan-ketentuan')),
                      ),
                      _Row(
                        icon: Icons.description_outlined,
                        label: 'Kebijakan Privasi',
                        onTap: () =>
                            context.push(Routes.terms('kebijakan-privasi')),
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
                            onTap: () =>
                                ref.read(themeModeProvider.notifier).cycle(),
                          ),
                          if (!isGuest)
                            _Row(
                              icon: Icons.settings_outlined,
                              label: 'Pengaturan akun',
                              onTap: () => context.push(Routes.settings),
                            ),
                          if (isGuest)
                            _Row(
                              icon: Icons.person_outline,
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
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          'Keluar dari akun?',
          style: AppTypography.h3(context.appColors.onSurface),
        ),
        content: Text(
          'Kamu yakin ingin keluar dari pokepedia.id?',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.error,
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

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = this.user;
    final isGuest = user == null;
    final displayName = isGuest
        ? 'Tamu'
        : (user.username ?? user.email.split('@').first);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          if (isGuest)
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(
                Icons.person_add_alt,
                size: 20,
                color: context.mutedForeground,
              ),
            )
          else
            UserAvatar(
              username: displayName,
              imageUrl: user.avatarUrl,
              size: 48,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySemibold(
                    !isGuest && user.isAdmin ? AppColors.gold : colors.onSurface,
                  ),
                ),
                if (isGuest)
                  Text(
                    'Masuk untuk koleksi & marketplace',
                    style: AppTypography.caption(context.mutedForeground),
                  )
                else if (user.username != null)
                  InkWell(
                    onTap: () =>
                        context.push(Routes.userProfile(user.username!)),
                    child: Text(
                      'Lihat profil',
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
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                title!.toUpperCase(),
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
                  if (i > 0) Divider(height: 1, color: context.borderColor),
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
              Text(
                hint!,
                style: AppTypography.caption(context.mutedForeground),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ports `AccountListSkeleton` — the placeholder shown while the session
/// resolves, so the page doesn't flash the guest state first.
class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );

    return ListView(
      padding: EdgeInsets.only(
        bottom: AppBottomNav.reservedSpace(context) + 12,
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(bottom: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.appColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(128, 14),
                  const SizedBox(height: 8),
                  bar(80, 10),
                ],
              ),
            ],
          ),
        ),
        for (var group = 0; group < 3; group++)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: bar(96, 10),
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
                      for (var row = 0; row < 3; row++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
                          ),
                          child: Row(
                            children: [
                              bar(20, 20),
                              const SizedBox(width: 12),
                              bar(112, 14),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
