import 'package:flutter/material.dart';

import '../models/pokemon_type.dart';

/// Ports the `/elements/{type}.webp` icons used throughout
/// `components/card/*` on the web (attack cost pips, weakness/resistance,
/// energy cards, the advanced-search type filter).
class TypeIcon extends StatelessWidget {
  const TypeIcon({super.key, required this.type, this.size = 20});

  final PokemonType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        type.iconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
