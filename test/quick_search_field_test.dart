import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/quick_search_field.dart';

CardModel _card() => const CardModel(
  id: 42,
  category: CardCategory.pokemon,
  nameId: 'Mewtwo ex',
  expansionCode: 'SV3',
  packSlug: 'sv3',
  collectorNumber: '183/197',
  rarity: 'SAR',
);

StoreModel _store() => const StoreModel(
  handle: 'toko-mew',
  storeName: 'Toko Mew',
  tagline: '',
  activeListingCount: 12,
  cityName: 'Bandung',
  isVerified: true,
  topRated: false,
  itemsSoldCount: 30,
  followersCount: 4,
);

Widget _harness(QuickSearchResults results) => ProviderScope(
  overrides: [quickSearchProvider.overrideWith((ref, query) async => results)],
  child: const MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Align(alignment: Alignment.topCenter, child: QuickSearchField()),
      ),
    ),
  ),
);

/// Tapping the search bar used to jump to the advanced-search form, which put
/// a filter builder between a collector and the card they already named. The
/// bar now answers in place, so what matters is that it waits for the query
/// to be worth running and then shows both kinds of result.
void main() {
  testWidgets('suggests stores and cards once the query is long enough', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(QuickSearchResults(cards: [_card()], stores: [_store()])),
    );

    await tester.enterText(find.byType(TextField), 'mew');
    // Web debounces 300ms before asking the server; nothing should be on
    // screen until it elapses.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Mewtwo ex'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Toko'), findsOneWidget);
    expect(find.text('Toko Mew'), findsOneWidget);
    expect(find.text('Bandung'), findsOneWidget);
    expect(find.text('Kartu'), findsOneWidget);
    expect(find.text('Mewtwo ex'), findsOneWidget);
    expect(find.text('183/197'), findsOneWidget);
    // The way out to the full results list, carrying what was typed.
    expect(find.textContaining("Cari semua untuk 'mew'"), findsOneWidget);
  });

  testWidgets('a single letter asks for nothing', (tester) async {
    await tester.pumpWidget(
      _harness(QuickSearchResults(cards: [_card()], stores: [_store()])),
    );

    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // One letter matches most of the catalog: a slow query and a useless list.
    expect(find.text('Mewtwo ex'), findsNothing);
    expect(find.textContaining('Cari semua'), findsNothing);
  });

  testWidgets('says so when a real query finds nothing', (tester) async {
    await tester.pumpWidget(_harness(QuickSearchResults.empty));

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tidak ada hasil'), findsOneWidget);
    // Still offers the full list — its fuzzy search corrects typos, so a
    // query with no suggestions can still have results.
    expect(find.textContaining("Cari semua untuk 'zzzz'"), findsOneWidget);
  });

  testWidgets('clearing the field closes the panel', (tester) async {
    await tester.pumpWidget(
      _harness(QuickSearchResults(cards: [_card()], stores: const [])),
    );

    await tester.enterText(find.byType(TextField), 'mew');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Mewtwo ex'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Mewtwo ex'), findsNothing);
  });
}
