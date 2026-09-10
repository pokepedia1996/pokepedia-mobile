import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import '../models/card_model.dart';

/// Ports web's `CardLanguageBadge` — the flag marking which language's print
/// a card is.
///
/// A flag rather than the two-letter code it used to show: the code needed
/// reading, a flag is recognised at badge size. The artwork is the same set
/// of SVGs the web serves, so the two clients show the same flags.
class CardLanguageBadge extends StatelessWidget {
  const CardLanguageBadge({super.key, required this.language, this.size = 16});

  final CardLanguage language;
  final double size;

  /// The same four files the web serves from `/public/flags`.
  String get _asset => switch (language) {
    CardLanguage.en => 'assets/images/flags/gb.svg',
    CardLanguage.jp => 'assets/images/flags/jp.svg',
    CardLanguage.id => 'assets/images/flags/id.svg',
  };

  @override
  Widget build(BuildContext context) {
    // `rounded-full ring-1 ring-border object-cover` on the web: a circular
    // crop of a rectangular flag, with a hairline ring so a white edge (JP,
    // ID) still reads against a light surface.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SvgPicture.asset(
        _asset,
        fit: BoxFit.cover,
        semanticsLabel: language.labelId,
      ),
    );
  }
}
