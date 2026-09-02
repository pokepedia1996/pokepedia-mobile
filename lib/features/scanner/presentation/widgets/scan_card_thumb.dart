import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../repository/models/scan_models.dart';

/// Ports `ScanCardThumb` — a scanned card's art at [width], held at
/// [cardAspect] so a missing or slow image reserves the right box instead of
/// reflowing the row around it.
class ScanCardThumb extends StatelessWidget {
  const ScanCardThumb({super.key, required this.card, this.width = 44});

  final ScanCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final url = card.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: width / cardAspect,
        child: url == null
            ? _placeholder(context)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.borderColor,
    child: Icon(
      LucideIcons.imageOff,
      size: width * 0.4,
      color: context.mutedForeground,
    ),
  );
}
