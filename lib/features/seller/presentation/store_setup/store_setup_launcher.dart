import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../../user/usecase/user_notifier.dart';
import 'store_setup_parts.dart';

/// The Jual tab for someone without a store: what selling here is worth,
/// what opening a store takes, and the way in.
///
/// The count is honest: a phone verified anywhere — Settings, a checkout —
/// is already one of the three done, and the flow will not ask for it.
class StoreSetupLauncher extends ConsumerWidget {
  const StoreSetupLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final phoneVerified =
        ref.watch(privateProfileProvider).valueOrNull?.phoneVerified ?? false;
    final done = phoneVerified ? 1 : 0;
    final navSpace = AppBottomNav.reservedSpace(context);

    return ColoredBox(
      color: palette.background,
      child: Stack(
        children: [
          ListView(
            // Clear of the button, which sits on the nav pill.
            padding: EdgeInsets.fromLTRB(16, 24, 16, navSpace + 90),
            children: [
              Text('Jual', style: setupHeading(28, palette.ink)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  setupSize(48),
                  0,
                  setupSize(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SetupHeadline(
                      first: '100% aman.',
                      second: '0% potongan.',
                      palette: palette,
                      size: 40,
                      lineHeight: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '3 menit untuk mulai berjualan di Pokepedia',
                      style: setupText(16, palette.muted),
                    ),
                  ],
                ),
              ),
              SetupCard(
                palette: palette,
                header: Container(
                  color: palette.chip,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Yang perlu disiapkan',
                          style: setupText(13, palette.ink, FontWeight.w700),
                        ),
                      ),
                      Text(
                        '$done dari 3',
                        style: setupText(12, palette.muted, FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                rows: [
                  SetupChecklistRow(
                    icon: LucideIcons.store,
                    title: 'Profil toko',
                    subtitle: 'Nama, foto & banner · bisa nanti',
                    meta: 'Opsional',
                    state: SetupRowState.optional,
                    palette: palette,
                  ),
                  SetupChecklistRow(
                    icon: LucideIcons.smartphone,
                    title: 'Verifikasi nomor HP',
                    subtitle: 'Biar pembeli & kurir bisa menghubungimu',
                    meta: phoneVerified ? 'Selesai' : '±1 mnt',
                    state: phoneVerified
                        ? SetupRowState.done
                        : SetupRowState.todo,
                    palette: palette,
                  ),
                  SetupChecklistRow(
                    icon: LucideIcons.mapPin,
                    title: 'Atur alamat pickup',
                    subtitle: 'Titik jemput kurir untuk semua kirimanmu',
                    meta: '±1 mnt',
                    state: SetupRowState.todo,
                    palette: palette,
                  ),
                  SetupChecklistRow(
                    icon: LucideIcons.truck,
                    title: 'Pilih kurir',
                    subtitle: 'Layanan pengiriman yang kamu terima',
                    meta: '±30 dtk',
                    state: SetupRowState.todo,
                    palette: palette,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 16,
                      color: palette.successText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Uang pembeli ditahan sampai kartu diterima.',
                        style: setupText(13, palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: navSpace + 6,
            child: SetupPrimaryButton(
              label: 'Mulai buka toko',
              icon: LucideIcons.arrowRight,
              palette: palette,
              onPressed: () => context.push(Routes.openStore),
            ),
          ),
        ],
      ),
    );
  }
}
