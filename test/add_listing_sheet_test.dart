import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/add_listing_sheet.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Tambahkan Listing" asks two questions — which cards, and how many of
/// each — and answers them with drafts. It used to hand a single card
/// straight to the ask form, which wanted a price before the seller had
/// finished saying what they were selling.
class _FakeRepo extends SellerListingsRepository {
  _FakeRepo._(SupabaseClient c) : super(c);

  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  List<({int cardId, int quantity})>? added;

  List<int>? get addedIds => added?.map((p) => p.cardId).toList();

  @override
  Future<({int added, String? error})> addDrafts(
    List<({int cardId, int quantity})> picks,
  ) async {
    added = picks;
    return (added: picks.length, error: null);
  }
}

CardModel _card(int id) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Pikachu $id',
  expansionCode: 'MA6',
  packSlug: 'ma6',
  collectorNumber: '03$id/130',
  rarity: 'AR',
);

Future<_FakeRepo> _open(WidgetTester tester) async {
  // A phone, and a tall one: at the default 800x600 the three-column grid
  // gives tiles ~430pt tall, so a card's label falls below the grid's
  // viewport the moment the selected strip appears and taps miss it.
  tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sellerListingsRepositoryProvider.overrideWithValue(repo),
        cardSearchPickerProvider.overrideWith(
          (ref, key) async => [
            for (final card in [_card(1), _card(2), _card(3)])
              if (key.language == null || card.language == key.language) card,
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAddListingSheet(context),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  // Debounced, then the provider resolves.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('asks for a query before searching anything', (tester) async {
    await _open(tester);
    expect(find.textContaining('Ketik minimal'), findsOneWidget);
  });

  testWidgets('nothing is offered until a card is ticked', (tester) async {
    await _open(tester);
    await _search(tester, 'pikachu');

    expect(find.text('3 kartu cocok'), findsOneWidget);
    // No CTA and no selected strip while the pick is empty.
    expect(find.textContaining('ke Draft'), findsNothing);
    expect(find.text('Terpilih'), findsNothing);
  });

  testWidgets('ticking cards counts them and offers them as drafts', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _search(tester, 'pikachu');

    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    await tester.tap(find.text('Pikachu 3'));
    await tester.pump();

    expect(find.text('Terpilih'), findsOneWidget);
    expect(find.text('Tambahkan 2 kartu ke Draft'), findsOneWidget);

    await tester.tap(find.text('Tambahkan 2 kartu ke Draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // In the order they were tapped — the strip reads as a history.
    expect(repo.addedIds, [1, 3]);
    expect(repo.added!.map((p) => p.quantity), [1, 1]);
  });

  testWidgets('tapping a picked card asks for another copy of it', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _search(tester, 'pikachu');

    // A playset is the commonest thing to add, and tapping used to undo the
    // pick instead: four taps ending with nothing selected.
    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();

    // One card, three copies — and the button says both.
    expect(find.text('Tambahkan 1 kartu · 3 lembar ke Draft'), findsOneWidget);

    await tester.tap(find.text('Tambahkan 1 kartu · 3 lembar ke Draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.added, [(cardId: 1, quantity: 3)]);
  });

  testWidgets('the stepper takes copies back off, then the card itself', (
    tester,
  ) async {
    await _open(tester);
    await _search(tester, 'pikachu');

    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    expect(find.text('Tambahkan 1 kartu · 2 lembar ke Draft'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Kurangi jumlah'));
    await tester.pump();
    expect(find.text('Tambahkan 1 kartu ke Draft'), findsOneWidget);

    // The last copy takes the card out of the pick — the way back from a
    // mistap.
    await tester.tap(find.bySemanticsLabel('Lepas dari pilihan'));
    await tester.pump();
    expect(find.textContaining('ke Draft'), findsNothing);
  });

  testWidgets('the language chips narrow the search', (tester) async {
    await _open(tester);
    await _search(tester, 'pikachu');
    expect(find.text('3 kartu cocok'), findsOneWidget);

    // The fixture is all Indonesian, so EN has to come back empty — which
    // only happens if the chip reaches the query rather than being
    // decoration over an unfiltered list.
    await tester.tap(find.text('EN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Tidak ada kartu'), findsOneWidget);

    await tester.tap(find.text('Semua'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('3 kartu cocok'), findsOneWidget);
  });

  testWidgets('the tap hint sits beside the first pick only', (tester) async {
    await _open(tester);
    await _search(tester, 'pikachu');
    const hint = 'Ketuk kartu untuk menambah, atur jumlahnya di bawah';

    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    expect(find.text(hint), findsOneWidget);

    // From the second card the thumbnails ran in under it.
    await tester.tap(find.text('Pikachu 2'));
    await tester.pump();
    expect(find.text(hint), findsNothing);
  });

  testWidgets('the picked strip steps aside while the keyboard is up', (
    tester,
  ) async {
    await _open(tester);
    await _search(tester, 'pikachu');
    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    expect(find.text('Terpilih'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(find.text('Terpilih'), findsNothing);
    // What was picked is still counted, and still one tap from the draft.
    expect(find.text('Tambahkan 1 kartu ke Draft'), findsOneWidget);

    tester.view.resetViewInsets();
    await tester.pump();
    expect(find.text('Terpilih'), findsOneWidget);
  });
}
