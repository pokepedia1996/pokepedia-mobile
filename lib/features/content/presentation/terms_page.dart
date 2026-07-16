import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Ports `app/terms/[slug]/page.tsx` — `components/legal/legal-markdown.tsx`.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key, required this.slug});

  final String slug;

  static const _titles = {
    'syarat-dan-ketentuan': 'Syarat & Ketentuan',
    'kebijakan-privasi': 'Kebijakan Privasi',
    'kondisi-kartu': 'Panduan Kondisi Kartu',
  };

  static const _bodies = {
    'syarat-dan-ketentuan':
        'Dengan menggunakan pokepedia.id, kamu setuju untuk bertransaksi secara jujur, '
            'mendeskripsikan kondisi kartu secara akurat, dan mengikuti alur escrow yang '
            'disediakan platform untuk melindungi pembeli dan penjual.',
    'kebijakan-privasi':
        'pokepedia.id mengumpulkan data akun, alamat, dan riwayat transaksi untuk '
            'keperluan pengiriman dan pencegahan penipuan. Data tidak dibagikan ke pihak '
            'ketiga tanpa persetujuanmu, kecuali mitra pengiriman dan pembayaran.',
    'kondisi-kartu':
        'NM (Near Mint): nyaris sempurna, tanpa cacat berarti.\n'
            'LP (Lightly Played): goresan halus di edge/surface.\n'
            'MP (Moderately Played): whitening atau goresan cukup terlihat.\n'
            'HP (Heavily Played): kerusakan signifikan namun masih utuh.\n'
            'Kartu ber-grade PSA mengikuti standar grading resmi PSA.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: Text(_titles[slug] ?? 'Ketentuan')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            _bodies[slug] ?? 'Konten belum tersedia.',
            style: AppTypography.bodySm(colors.onSurface),
          ),
        ),
      ),
    );
  }
}
