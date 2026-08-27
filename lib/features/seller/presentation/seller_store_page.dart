import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/store_profile.dart';
import '../usecase/store_profile_notifier.dart';

/// Ports the "Toko" section of web's seller workspace nav
/// (`RAIL_BY_SECTION.store`): Profil toko, Kurir, Chat.
///
/// This used to be a single row that deep-linked to the public storefront,
/// which is the one thing the section *isn't* — web's Toko is where the
/// seller configures the shop, not where they look at it.
class SellerStorePage extends ConsumerWidget {
  const SellerStorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storeProfileProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Gagal memuat toko',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(storeProfileProvider),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (profile) {
            if (profile == null) {
              return const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Belum punya toko',
                description:
                    'Buka toko dulu di pokepedia.id, lalu kelola dari sini.',
              );
            }
            return _body(context, ref, profile);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, StoreProfile profile) {
    final colors = context.appColors;
    // A store that hasn't been named yet has no slug; the storefront is
    // still reachable by username, which is what the repository falls back
    // to. Without this the button is dead for exactly the sellers most
    // likely to want to look at their shop.
    final handle =
        profile.storeHandle ?? ref.watch(authProvider).valueOrNull?.username;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storeProfileProvider);
        await ref.read(storeProfileProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Toko', style: AppTypography.h1(colors.onSurface)),
          const SizedBox(height: 4),
          Text(
            'Atur identitas toko, alamat pengirim, kurir, dan chat pembeli.',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 16),

          _StoreHeader(profile: profile),

          // The gaps that stop a store trading, surfaced here rather than
          // waiting for a failed booking to explain them.
          if (!profile.hasPickupAddress) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.location_off_outlined,
              tone: colors.error,
              message:
                  'Alamat pengirim belum lengkap. Kurir tidak bisa menjemput '
                  'paket sampai kamu mengisinya.',
              actionLabel: 'Lengkapi',
              onAction: () => context.push(Routes.sellerStoreProfile),
            ),
          ],
          if (profile.onVacation) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.beach_access_outlined,
              tone: context.appSemantic.condMp,
              message: _vacationMessage(profile),
              actionLabel: 'Atur',
              onAction: () => context.push(Routes.sellerStoreProfile),
            ),
          ],

          const SizedBox(height: 20),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                _Row(
                  icon: Icons.person_outline,
                  label: 'Profil toko',
                  description: 'Nama, URL, tentang, alamat, dan libur',
                  onTap: () => context.push(Routes.sellerStoreProfile),
                ),
                Divider(height: 1, color: context.borderColor),
                _Row(
                  icon: Icons.local_shipping_outlined,
                  label: 'Kurir',
                  description: profile.acceptedCourierServices.isEmpty
                      ? 'Semua layanan diterima'
                      : '${profile.acceptedCourierServices.length} layanan '
                            'dipilih',
                  onTap: () => context.push(Routes.sellerCouriers),
                ),
                Divider(height: 1, color: context.borderColor),
                _Row(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat',
                  description: 'Pesan dari pembeli',
                  onTap: () => context.push(Routes.chat),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: handle == null
                ? null
                : () => context.push(Routes.storeDetail(handle)),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Lihat toko seperti pembeli'),
          ),
        ],
      ),
    );
  }

  static String _vacationMessage(StoreProfile profile) {
    final mode = VacationMode.fromRaw(profile.vacationMode);
    final days = profile.vacationDaysLeft;
    final label = mode?.label ?? 'Libur';
    if (days == null) return '$label sedang aktif.';
    return days <= 0
        ? '$label berakhir hari ini.'
        : '$label aktif, sisa $days hari.';
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.profile});

  final StoreProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.secondary,
            backgroundImage: profile.storeLogoUrl == null
                ? null
                : NetworkImage(profile.storeLogoUrl!),
            child: profile.storeLogoUrl != null
                ? null
                : Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: context.mutedForeground,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.storeName ?? 'Toko tanpa nama',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySemibold(colors.onSurface),
                      ),
                    ),
                    if (profile.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 15, color: colors.primary),
                    ],
                  ],
                ),
                if (profile.storeSlug != null)
                  Text(
                    'pokepedia.id/market/${profile.storeSlug}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${profile.itemsSoldCount} terjual · '
                  '${profile.followersCount} pengikut',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          _StatusChip(profile: profile),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.profile});

  final StoreProfile profile;

  @override
  Widget build(BuildContext context) {
    final (label, color) = profile.onVacation
        ? ('Libur', context.appSemantic.condMp)
        : profile.isActive
        ? ('Aktif', context.appSemantic.success)
        : ('Nonaktif', context.mutedForeground);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: AppTypography.badge(color)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color tone;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption(context.appColors.onSurface),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: tone,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel),
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
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    description,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}
