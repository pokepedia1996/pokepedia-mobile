import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/catalog_language_provider.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../../shared/widgets/app_network_image.dart';

/// "Pilih TCG": a tile per catalog, two to a row. A tap switches the catalog
/// being browsed and opens Pencarian on it.
///
/// The catalogs are `catalog_categories`' (see [catalogLanguagesProvider]),
/// so a new one appears here without a release; one without catalog artwork
/// shows its flag. In the app's catalog order (see
/// [orderCatalogLanguages]): Indonesian, then A–Z.
class TcgPickerSection extends ConsumerWidget {
  const TcgPickerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = watchCatalogLanguages(ref);
    if (languages.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < languages.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TcgTile(language: languages[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < languages.length
                      ? _TcgTile(language: languages[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TcgTile extends ConsumerWidget {
  const _TcgTile({required this.language});

  final CardLanguage language;

  /// CDN logos match pokemon_web. Bundled art is the offline fallback.
  /// The designs pad
  /// each one so the four read at the same weight.
  static const _logos = {
    'id': (
      'assets/images/tcg/pokemon-id.png',
      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    'jp': (
      'assets/images/tcg/pokemon-jp.png',
      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    'en': (
      'assets/images/tcg/pokemon-en.png',
      EdgeInsets.symmetric(horizontal: 26, vertical: 10),
    ),
    'cn': (
      'assets/images/tcg/pokemon-cn.png',
      EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final logo = _logos[language.raw];
    final name = 'Pokémon ${language.shortLabel}';

    return Semantics(
      button: true,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(catalogLanguageProvider.notifier).set(language);
          context.go(Routes.search);
        },
        child: Column(
          children: [
            Container(
              height: 84,
              width: double.infinity,
              padding: logo?.$2 ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: logo == null
                  ? Center(
                      child: CardLanguageBadge(language: language, size: 40),
                    )
                  : cachedNetworkImage(
                      'https://cdn.pokepedia.id/tcg/logos/pokemon-${language.raw}.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Image.asset(logo.$1, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.urbanist(
                fontSize: 11,
                height: 14 / 11,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
