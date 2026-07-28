import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Ports `components/store/seller-avatar.tsx` — a circular seller/store
/// image, falling back to the name's first letter when there's no logo.
class SellerAvatar extends StatelessWidget {
  const SellerAvatar({super.key, required this.name, this.imageUrl, this.size = 18});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final textStyle = TextStyle(
      fontSize: size * 0.5,
      fontWeight: FontWeight.w600,
      color: context.mutedForeground,
    );
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.secondary,
        alignment: Alignment.center,
        child: imageUrl == null || imageUrl!.isEmpty
            ? Text(initial, style: textStyle)
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (context, error, stackTrace) => Text(initial, style: textStyle),
              ),
      ),
    );
  }
}
