import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/card_model.dart';

/// Which language's catalog the buyer is browsing, ported from
/// `contexts/catalog-language-context.tsx` and `lib/catalog/language.ts`.
///
/// The web encodes this in the URL (`/en/expansions`, `/jp/expansions`) for
/// the two localized paths — expansions and advanced search. There are no
/// URLs to localize here, so it's app state instead, and it scopes the same
/// two surfaces: the expansions catalog and card search. Market, portfolio
/// and orders are unaffected, exactly as on the web.
///
/// Not persisted across restarts, matching the app's theme setting — the
/// project has no `shared_preferences` dependency yet.
class CatalogLanguageNotifier extends Notifier<CardLanguage> {
  @override
  CardLanguage build() => CardLanguage.id;

  void set(CardLanguage language) => state = language;
}

final catalogLanguageProvider =
    NotifierProvider<CatalogLanguageNotifier, CardLanguage>(
      CatalogLanguageNotifier.new,
    );

/// The order the switch renders them in — `CATALOG_LANGUAGES` on the web.
const catalogLanguages = [CardLanguage.id, CardLanguage.en, CardLanguage.jp];
