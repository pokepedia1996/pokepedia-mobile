import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/utils/courier.dart';

/// Ports `features/shipment/components/courier-tracking-link.tsx`.
///
/// Two shapes, as on web. A courier whose tracking page takes the resi in its
/// URL gets a single `Lacak di <courier>` link. Everyone else only publishes
/// a form, so the buyer is told to paste the number and handed the page —
/// pretending a landing page is a deep link just loses them on arrival.
class CourierTrackingLink extends StatelessWidget {
  const CourierTrackingLink({
    super.key,
    required this.courier,
    required this.trackingNumber,
  });

  final String? courier;
  final String? trackingNumber;

  @override
  Widget build(BuildContext context) {
    final resi = trackingNumber?.trim();
    if (resi == null || resi.isEmpty) return const SizedBox.shrink();

    final resolved = getTrackingUrl(courier, resi);
    final label = courierDisplayName(courier) ?? 'kurir';

    if (resolved.mode == TrackingMode.direct) {
      return _Link(label: 'Lacak di $label', url: resolved.url);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Salin nomor resi, lalu tempelkan di kolom pelacakan $label.',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 6),
        _Link(label: 'Buka halaman pelacakan $label', url: resolved.url),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url});

  final String label;
  final String url;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (opened) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka halaman kurir.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionSemibold(colors.primary),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.externalLink, size: 12, color: colors.primary),
          ],
        ),
      ),
    );
  }
}
