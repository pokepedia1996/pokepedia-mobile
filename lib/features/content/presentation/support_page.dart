import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Ports `app/support/page.tsx`.
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _faqs = [
    (
      'Bagaimana cara menjual kartu?',
      'Buka Dashboard Penjual dari menu Akun, lalu tambahkan listing baru lengkap dengan foto dan kondisi kartu.',
    ),
    (
      'Berapa lama proses pengiriman?',
      'Penjual wajib mengirim dalam 2x24 jam setelah pembayaran dikonfirmasi. Estimasi kurir bervariasi sesuai jasa yang dipilih.',
    ),
    (
      'Apa itu escrow payment?',
      'Dana pembeli ditahan platform hingga barang diterima dan dikonfirmasi, melindungi kedua belah pihak dari penipuan.',
    ),
    (
      'Bagaimana jika barang tidak sesuai?',
      'Ajukan sengketa dari halaman detail pesanan dalam 3x24 jam setelah barang diterima.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Pertanyaan Umum', style: AppTypography.h3(colors.onSurface)),
            const SizedBox(height: 12),
            for (final (q, a) in _faqs)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q, style: AppTypography.bodySmSemibold(colors.onSurface)),
                    const SizedBox(height: 6),
                    Text(a, style: AppTypography.bodySm(context.mutedForeground)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Masih butuh bantuan?', style: AppTypography.bodySmSemibold(colors.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Hubungi tim kami di support@pokepedia.id',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
