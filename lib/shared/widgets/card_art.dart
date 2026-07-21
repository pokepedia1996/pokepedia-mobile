import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';

/// Pokemon-card artwork (245:342 aspect ratio). Renders [imageUrl] when
/// present (real catalog data); otherwise falls back to the bundled
/// `backcard.webp` placeholder — used everywhere dummy data still supplies
/// no real image.
class CardArt extends StatelessWidget {
  const CardArt({super.key, this.imageUrl, this.borderRadius = AppRadius.md});

  final String? imageUrl;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 245 / 342,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Theme.of(context).colorScheme.secondary,
          child: imageUrl == null
              ? Image.asset('assets/images/backcard.webp', fit: BoxFit.cover)
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Image.asset('assets/images/backcard.webp', fit: BoxFit.cover);
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset('assets/images/backcard.webp', fit: BoxFit.cover);
                  },
                ),
        ),
      ),
    );
  }
}
