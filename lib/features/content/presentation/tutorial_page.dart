import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Ports `app/tutorial/page.tsx` — `components/tutorial/tutorial-content.tsx`.
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  static const _steps = [
    (
      Icons.search,
      'Jelajahi Ekspansi',
      'Cari kartu favoritmu lewat tab Ekspansi atau Pencarian Lanjutan.',
    ),
    (
      Icons.style_outlined,
      'Bangun Koleksi & Deck',
      'Tandai kartu yang kamu miliki dan susun deck kompetitifmu di tab Koleksi.',
    ),
    (
      Icons.storefront_outlined,
      'Jual Beli di Market',
      'Pasang listing atau ajukan penawaran langsung dari halaman kartu.',
    ),
    (
      Icons.local_shipping_outlined,
      'Transaksi Aman',
      'Pembayaran ditahan platform (escrow) hingga barang diterima pembeli.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _steps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final (icon, title, desc) = _steps[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(icon, color: colors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. $title',
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
