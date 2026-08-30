import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_poster.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_share_sheet.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

const _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 40,
  cityName: 'Jakarta',
  isVerified: true,
  topRated: true,
  itemsSoldCount: 79,
  followersCount: 12,
);

List<ListingModel> _listings(int count) => List.generate(
  count,
  (i) => ListingModel(
    id: i,
    sellerId: 'seller-1',
    slug: 'listing-$i',
    side: ListingSide.ask,
    price: 10000,
    condition: CardCondition.nm,
    quantity: 1,
    card: const CardModel(
      id: 1,
      category: CardCategory.pokemon,
      nameId: 'Pikachu',
      expansionCode: 'SV2a',
      packSlug: 'sv2a',
      collectorNumber: '025/165',
      rarity: 'Rare',
    ),
    storeSlug: 'toko',
    storeName: 'Toko Ash',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
  ),
);

Future<void> _open(WidgetTester tester, List<ListingModel> listings) async {
  // A phone, not the 800×600 default: the sheet's height budget is the
  // whole point of the layout, and a landscape surface never tests it.
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeListingsProvider(
          _store.handle,
        ).overrideWith((ref) async => listings),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StoreShareSheet(
            store: _store,
            positivePct: 100,
            feedbackScore: 17,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final capacity = StorePoster.capacity;

  // Page one holds one card fewer than the rest, so three pages is
  // 11 + 12 + 4 rather than a round multiple of the capacity.
  final threePages = capacity * 2 + 3;

  // A tap that lands on nothing would let a selection test pass without the
  // selection ever changing — the off-screen carousel pages make that easy
  // to do by accident.
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('every page is on screen the moment the sheet opens', (
    tester,
  ) async {
    // The user picks from what they can see rather than opting into a batch
    // and hoping — so the page count is visible without any extra tap.
    await _open(tester, _listings(threePages));

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1/3 dipilih'), findsOneWidget);
  });

  testWidgets('only the first poster is selected to start with', (
    tester,
  ) async {
    // Page one already points at everything it leaves out, so it stands on
    // its own; posting a store's whole book unasked is the rarer intent.
    await _open(tester, _listings(capacity * 2 + 1));

    expect(find.text('1/3 dipilih'), findsOneWidget);
    expect(find.text('Bagikan poster'), findsOneWidget);
  });

  testWidgets('"Pilih semua" takes every page', (tester) async {
    await _open(tester, _listings(threePages));

    await tester.tap(find.text('Pilih semua'));
    await tester.pump();

    expect(find.text('3/3 dipilih'), findsOneWidget);
    expect(find.text('Bagikan 3 poster'), findsOneWidget);
  });

  testWidgets('"Batal pilih" clears the selection and disables sharing', (
    tester,
  ) async {
    // Reachable on purpose now, so the button says what to do about it
    // rather than greying out unexplained.
    await _open(tester, _listings(threePages));

    await tester.tap(find.text('Pilih semua'));
    await tester.pump();
    await tester.tap(find.text('Batal pilih'));
    await tester.pump();

    expect(find.text('0/3 dipilih'), findsOneWidget);
    expect(find.text('Pilih poster dulu'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('each bulk button is dead when it would change nothing', (
    tester,
  ) async {
    // The pair doubles as a read-out of the current state.
    await _open(tester, _listings(threePages));

    OutlinedButton button(String label) => tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, label),
    );

    expect(button('Pilih semua').onPressed, isNotNull);
    expect(button('Batal pilih').onPressed, isNotNull);

    await tester.tap(find.text('Pilih semua'));
    await tester.pump();
    expect(button('Pilih semua').onPressed, isNull);

    await tester.tap(find.text('Batal pilih'));
    await tester.pump();
    expect(button('Batal pilih').onPressed, isNull);
  });

  testWidgets('tapping a poster toggles it', (tester) async {
    await _open(tester, _listings(threePages));

    // Page one starts in, so a tap takes it out.
    await tester.tap(find.byType(StorePoster).first);
    await tester.pump();
    expect(find.text('0/3 dipilih'), findsOneWidget);

    await tester.tap(find.byType(StorePoster).first);
    await tester.pump();
    expect(find.text('1/3 dipilih'), findsOneWidget);
  });

  testWidgets('a poster off the default selection can be added', (
    tester,
  ) async {
    await _open(tester, _listings(threePages));

    // The second page has to be swiped into view before it can be tapped.
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StorePoster).at(1));
    await tester.pump();

    expect(find.text('2/3 dipilih'), findsOneWidget);
    expect(find.text('Bagikan 2 poster'), findsOneWidget);
  });

  testWidgets('a store that fits on one poster shows no picker', (
    tester,
  ) async {
    await _open(tester, _listings(4));

    expect(find.byType(PageView), findsNothing);
    expect(find.textContaining('dipilih'), findsNothing);
    expect(find.text('Pilih semua'), findsNothing);
    expect(find.text('Bagikan poster'), findsOneWidget);
  });

  testWidgets('an empty side says so instead of showing a blank poster', (
    tester,
  ) async {
    await _open(tester, const []);

    expect(find.byType(StorePoster), findsNothing);
    expect(find.text('Toko ini belum menjual kartu apa pun.'), findsOneWidget);
  });

  testWidgets('switching sides resets the selection', (tester) async {
    // Page 2 of WTS and page 2 of WTB are different posters, so carrying a
    // page-index selection across the toggle would drop the wrong one.
    await _open(tester, _listings(threePages));

    await tester.tap(find.text('Pilih semua'));
    await tester.pump();
    expect(find.text('3/3 dipilih'), findsOneWidget);

    await tester.tap(find.textContaining('WTB'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('WTS'));
    await tester.pumpAndSettle();

    expect(find.text('1/3 dipilih'), findsOneWidget);
  });
}
