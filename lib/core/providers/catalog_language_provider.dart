import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/card_model.dart';
import 'supabase_provider.dart';

/// Which language's catalog the buyer is browsing, ported from
/// `contexts/catalog-language-context.tsx` and `lib/catalog/language.ts`.
///
/// The web encodes this in the URL (`/en/expansions`, `/jp/expansions`) for
/// the two localized paths — expansions and advanced search. There are no
/// URLs to localize here, so it's app state instead, and it scopes the same
/// two surfaces: the expansions catalog and card search. Market, portfolio
/// and orders are unaffected, exactly as on the web.
///
class CatalogLanguageNotifier extends Notifier<CardLanguage> {
  @override
  CardLanguage build() => CardLanguage.id;

  void set(CardLanguage language) => state = language;
}

final catalogLanguageProvider =
    NotifierProvider<CatalogLanguageNotifier, CardLanguage>(
      CatalogLanguageNotifier.new,
    );

/// The catalogs to offer, in the switch's order: `catalog_categories` on
/// the server, so a new catalog is a row there rather than an app release.
///
/// Pokémon's only, for now: the other TCGs will be rows too, but nothing in
/// the app browses them yet. Until the read lands, and whenever it fails
/// (offline, or a server without the table yet), the list is the one this
/// build ships with, [CardLanguage.builtIn].
final catalogLanguagesProvider = FutureProvider<List<CardLanguage>>((
  ref,
) async {
  try {
    final rows = await ref
        .read(supabaseClientProvider)
        .from('catalog_categories')
        .select('code, label, name, icon_url, in_scanner')
        .eq('game', 'pokemon')
        .eq('is_active', true)
        .order('sort_order');
    final languages = [
      for (final row in rows)
        if (CardLanguage.fromCatalogRow(row) case final language?) language,
    ];
    CardLanguage.useServerList(languages);
  } catch (_) {
    // Keep whatever list is in hand.
  }
  return CardLanguage.known;
});

/// The list to draw right now: the server's once it is in, the built-in
/// one until then, so no switch ever renders empty. In
/// [orderCatalogLanguages]' order, so every picker in the app agrees.
List<CardLanguage> watchCatalogLanguages(WidgetRef ref) => orderCatalogLanguages(
  ref.watch(catalogLanguagesProvider).valueOrNull ?? CardLanguage.known,
);

/// The order catalogs are offered in: Indonesian first, as the home
/// catalog, then the rest A–Z by label — whatever order the server lists
/// them in (`catalog_categories.sort_order` decides only what the web
/// shows).
List<CardLanguage> orderCatalogLanguages(List<CardLanguage> languages) {
  int rank(CardLanguage l) => l == CardLanguage.id ? 0 : 1;
  return [...languages]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.shortLabel.toUpperCase().compareTo(b.shortLabel.toUpperCase());
  });
}
