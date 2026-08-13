import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';

/// Ports `app/orders/[slug]/open-dispute/page.tsx`.
class OrderDisputePage extends StatefulWidget {
  const OrderDisputePage({super.key, required this.slug});

  final String slug;

  @override
  State<OrderDisputePage> createState() => _OrderDisputePageState();
}

class _OrderDisputePageState extends State<OrderDisputePage> {
  static const _reasons = [
    'Barang tidak sesuai deskripsi',
    'Barang tidak sampai',
    'Barang rusak saat pengiriman',
    'Lainnya',
  ];

  String _reason = _reasons.first;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
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
            Text(
              'Alasan sengketa',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 8),
            for (final reason in _reasons)
              InkWell(
                onTap: () => setState(() => _reason = reason),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _reason == reason
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: _reason == reason
                            ? colors.primary
                            : context.mutedForeground,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        reason,
                        style: AppTypography.bodySm(colors.onSurface),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Detail tambahan',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Jelaskan masalah yang kamu alami...',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pengajuan sengketa terkirim')),
                );
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: colors.error,
              ),
              child: const Text('Ajukan Sengketa'),
            ),
          ],
        ),
      ),
    );
  }
}
