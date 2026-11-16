import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/scribble_drawing.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../../user/usecase/user_notifier.dart';
import 'store_setup_parts.dart';

/// The Jual tab for someone without a store: what selling here is worth,
/// what opening a store takes, and the way in.
///
/// The count is honest: a phone verified anywhere — Settings, a checkout —
/// is already one of the three done, and the flow will not ask for it.
///
/// The page is the app's; the two cards on it are paper — cream and white
/// — in either theme, so they are drawn in the light one.
class StoreSetupLauncher extends ConsumerWidget {
  const StoreSetupLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final phoneVerified =
        ref.watch(privateProfileProvider).valueOrNull?.phoneVerified ?? false;
    final done = phoneVerified ? 1 : 0;
    final navSpace = AppBottomNav.reservedSpace(context);
    final background = Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          ListView(
            // The page scrolls on under the button, which sits on the nav
            // pill; this keeps the last of it reachable above both.
            padding: EdgeInsets.fromLTRB(16, 24, 16, navSpace + 120),
            children: [
              Text('Jual', style: setupHeading(30, palette.ink)),
              const SizedBox(height: 16),
              Theme(
                data: AppTheme.light,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CoretanReveal(child: _Hero()),
                    const SizedBox(height: 14),
                    CoretanReveal(
                      delay: const Duration(milliseconds: 110),
                      child: _Checklist(
                        done: done,
                        phoneVerified: phoneVerified,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 17,
                      color: palette.brand,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Uang pembeli ditahan sampai kartu diterima.',
                        style: setupText(15, palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // The page fades out under the button rather than ending at its
          // edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: navSpace + 96,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background.withValues(alpha: 0),
                      background,
                      background,
                    ],
                    stops: const [0, .45, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: navSpace + 10,
            child: CoretanButton(
              label: 'Mulai buka toko',
              onPressed: () => context.push(Routes.openStore),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cream and pattern, the stall drawing itself, and the promise.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.onbLine, width: 1.2),
      ),
      child: CoretanBackground(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          child: Column(
            children: [
              SizedBox(
                height: setupSize(160),
                child: const ScribbleDrawing(drawing: 'toko_lapak'),
              ),
              const SizedBox(height: 6),
              const CoretanEyebrow('buka toko gratis', size: 21, center: true),
              const SizedBox(height: 8),
              SetupHeadline(
                first: '100% aman.',
                second: '0% potongan.',
                palette: palette,
                size: 36,
                lineHeight: 38,
                center: true,
              ),
              const SizedBox(height: 8),
              Text(
                '3 menit untuk mulai berjualan di Pokepedia',
                textAlign: TextAlign.center,
                style: setupText(16, palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.done, required this.phoneVerified});

  final int done;
  final bool phoneVerified;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    // Each icon draws itself a little after the one above it.
    Widget icon(String drawing, int row) => ScribbleDrawing(
      drawing: drawing,
      size: 46,
      stepMs: 40,
      delay: Duration(milliseconds: 520 + 110 * row),
    );
    Widget note(String text, {Color? color}) =>
        Text(text, style: AppTypography.hand(color ?? palette.ink, size: 18));

    return SetupCard(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Yang perlu disiapkan',
                style: setupText(16, palette.ink, FontWeight.w800),
              ),
            ),
            Text(
              '$done dari 3',
              style: AppTypography.hand(palette.brand, size: 19),
            ),
          ],
        ),
      ),
      rows: [
        SetupChecklistRow(
          icon: icon('toko_toko', 0),
          title: 'Profil toko',
          subtitle: 'Nama, foto & banner · bisa nanti',
          meta: note('opsional', color: palette.brand),
        ),
        SetupChecklistRow(
          icon: icon('toko_hp', 1),
          title: 'Verifikasi nomor HP',
          subtitle: 'Biar pembeli & kurir bisa menghubungimu',
          meta: phoneVerified
              ? note('selesai', color: palette.successText)
              : note('±1 mnt'),
        ),
        SetupChecklistRow(
          icon: icon('toko_pin', 2),
          title: 'Atur alamat pickup',
          subtitle: 'Titik jemput kurir untuk semua kirimanmu',
          meta: note('±1 mnt'),
        ),
        SetupChecklistRow(
          icon: icon('toko_truk', 3),
          title: 'Pilih kurir',
          subtitle: 'Layanan pengiriman yang kamu terima',
          meta: note('±30 dtk'),
        ),
      ],
    );
  }
}
