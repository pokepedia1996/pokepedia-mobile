import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/quick_search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

CardModel _numbered(int i) => CardModel(
  id: i,
  category: CardCategory.pokemon,
  nameId: 'Kartu $i',
  expansionCode: 'SV3',
  packSlug: 'sv3',
  collectorNumber: '$i/197',
  rarity: 'SAR',
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('clearing the field drops the results', (tester) async {
    // The panel itself stays: an empty field is where the recent searches
    // are shown, so what goes away is the card rows, not the dropdown.
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

  testWidgets('an empty field with no history shows no panel', (tester) async {
    // Focus alone used to open a card holding one line of grey instruction,
    // which covered the page the field sits on and said nothing.
    await tester.pumpWidget(
      _harness(QuickSearchResults(cards: [_card()], stores: const [])),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byKey(QuickSearchField.panelKey), findsNothing);
  });

  testWidgets('an empty field opens on past searches once there are any', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recent_searches': ['pikachu 130'],
    });
    await tester.pumpWidget(
      _harness(QuickSearchResults(cards: [_card()], stores: const [])),
    );
    // The provider loads from disk a microtask after its first read.
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('Pencarian terakhir'), findsOneWidget);
    expect(find.text('pikachu 130'), findsOneWidget);
  });

  testWidgets('the panel stops at 65% of the screen', (tester) async {
    await tester.pumpWidget(
      _harness(
        QuickSearchResults(
          cards: [for (var i = 1; i <= 40; i++) _numbered(i)],
          stores: const [],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'kartu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final panel = tester.getSize(find.byKey(QuickSearchField.panelKey));
    // Forty rows want far more than this, so the cap is what is being read
    // here rather than the content happening to be short.
    expect(panel.height, lessThanOrEqualTo(screen * 0.65 + 0.5));
    expect(panel.height, greaterThan(screen * 0.5));
  });

  testWidgets('a spinner marks the wait, not a bar', (tester) async {
    // Never completes: the panel stays in its loading stage for the assert.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickSearchProvider.overrideWith(
            (ref, query) => Completer<QuickSearchResults>().future,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: QuickSearchField(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'mew');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
