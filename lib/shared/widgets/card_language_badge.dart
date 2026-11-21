import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_model.dart';

/// Ports web's `CardLanguageBadge` — the flag marking which language's print
/// a card is.
///
/// A flag rather than the two-letter code it used to show: the code needed
/// reading, a flag is recognised at badge size. The artwork is the same set
/// of SVGs the web serves, so the two clients show the same flags.
///
/// The catalogs come from the server now, so a badge can meet one this build
/// has no artwork for: it then loads the web's file ([CardLanguage.iconUrl]),
/// and failing that shows the code.
class CardLanguageBadge extends StatelessWidget {
  const CardLanguageBadge({super.key, required this.language, this.size = 16});

  final CardLanguage language;
  final double size;

  /// The flags bundled with the app, the same files the web serves from
  /// `/public/flags`. English shows the US flag; its label stays "EN".
  static const _bundled = {
    'id': 'assets/images/flags/id.svg',
    'en': 'assets/images/flags/us.svg',
    'jp': 'assets/images/flags/jp.svg',
    'cn': 'assets/images/flags/cn.svg',
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
      child: _artwork(context),
    );
  }

  Widget _artwork(BuildContext context) {
    final asset = _bundled[language.raw];
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        fit: BoxFit.cover,
        semanticsLabel: language.labelId,
      );
    }
    final remote = _remoteUrl(language.iconUrl);
    if (remote != null) {
      return SvgPicture.network(
        remote,
        fit: BoxFit.cover,
        semanticsLabel: language.labelId,
        placeholderBuilder: (context) => _code(context),
        errorBuilder: (context, _, __) => _code(context),
      );
    }
    return _code(context);
  }

  /// The code itself, for a catalog with no artwork at all.
  Widget _code(BuildContext context) => ColoredBox(
    color: context.appColors.secondary,
    child: Center(
      child: Text(
        language.shortLabel,
        maxLines: 1,
        style: AppTypography.badge(
          context.mutedForeground,
        ).copyWith(fontSize: size * 0.38),
      ),
    ),
  );

  /// A path on the web (`/flags/cn.svg`) as a full URL; a full URL as is.
  static String? _remoteUrl(String? iconUrl) {
    final value = iconUrl?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('https://')) return value;
    if (!value.startsWith('/')) return null;
    return '${AppConfig.appUrl.replaceFirst(RegExp(r'/+$'), '')}$value';
  }
}
