import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/add_listing_sheet.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Tambahkan Listing" asks one question — which cards — and answers it with
/// drafts. It used to hand a single card straight to the ask form, which
/// wanted a price before the seller had finished saying what they were
/// selling.
class _FakeRepo extends SellerListingsRepository {
  _FakeRepo._(SupabaseClient c) : super(c);

  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  List<int>? addedIds;

  @override
  Future<({int added, String? error})> addDrafts(List<int> cardIds) async {
    addedIds = cardIds;
    return (added: cardIds.length, error: null);
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
          (ref, query) async => [_card(1), _card(2), _card(3)],
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
  });

  testWidgets('tapping a ticked card lets it go again', (tester) async {
    await _open(tester);
    await _search(tester, 'pikachu');

    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    expect(find.text('Tambahkan 1 kartu ke Draft'), findsOneWidget);

    await tester.tap(find.text('Pikachu 1'));
    await tester.pump();
    expect(find.textContaining('ke Draft'), findsNothing);
  });
}
