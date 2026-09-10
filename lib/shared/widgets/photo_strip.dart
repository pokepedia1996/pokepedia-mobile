import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import 'image_lightbox.dart';

/// Ports `components/ui/photo-strip.tsx` — a row of thumbnails that open
/// full-screen, with the overflow folded onto the last tile.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.srcs,
    this.max = 4,
    this.thumbSize = 64,
  });

  final List<String> srcs;

  /// How many tiles to draw before collapsing the rest into a `+N` badge.
  final int max;
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    if (srcs.isEmpty) return const SizedBox.shrink();

    final visible = srcs.take(max).toList();
    final overflow = srcs.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < visible.length; i++)
          _Thumb(
            src: visible[i],
            size: thumbSize,
            // Web stacks the count over the last visible tile rather than
            // adding one, so the strip keeps its width.
            overflow: i == visible.length - 1 && overflow > 0 ? overflow : 0,
            onTap: () => showImageLightbox(context, imageUrl: visible[i]),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.src,
    required this.size,
    required this.overflow,
    required this.onTap,
  });

  final String src;
  final double size;
  final int overflow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.appColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: context.borderColor),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              src,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                size: size * 0.3,
                color: context.mutedForeground,
              ),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const SizedBox.shrink(),
            ),
            if (overflow > 0)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Text(
                    '+$overflow',
                    style: AppTypography.bodySmSemibold(Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
