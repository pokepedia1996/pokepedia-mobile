import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';

/// Placeholder Pokemon-card artwork (245:342 aspect ratio) backed by the
/// bundled `backcard.webp` asset — stands in for real card photography
/// while this pass only ports the UI with dummy data.
class CardArt extends StatelessWidget {
  const CardArt({super.key, this.borderRadius = AppRadius.md});

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 245 / 342,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Theme.of(context).colorScheme.secondary,
          child: Image.asset(
            'assets/images/backcard.webp',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
