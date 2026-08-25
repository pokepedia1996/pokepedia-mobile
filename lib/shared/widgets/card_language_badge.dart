import 'package:flutter/material.dart';

import '../models/card_model.dart';

/// Ports web's `CardLanguageBadge` — the flag marking which language's print
/// a card is.
///
/// Uses the flag glyph rather than the two-letter code it used to show: the
/// code needed reading, a flag is recognised at badge size. Emoji flags also
/// mean no per-language image assets to bundle or proxy.
class CardLanguageBadge extends StatelessWidget {
  const CardLanguageBadge({super.key, required this.language, this.size = 16});

  final CardLanguage language;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          language.flag,
          // The glyph carries its own colour, so it only needs sizing.
          // `height: 1` keeps it centred — flag emoji have generous default
          // line metrics that otherwise push them off-centre in a tight box.
          style: TextStyle(fontSize: size * 0.92, height: 1),
          semanticsLabel: language.labelId,
        ),
      ),
    );
  }
}
