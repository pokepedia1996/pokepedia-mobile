import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/card_listings_section.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/store_identity.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/widgets/seller_rating_badge.dart';

const _card = CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Moltres',
  expansionCode: 'M-P',
  packSlug: 'm-p',
  collectorNumber: '028/M-P',
  rarity: 'Promo',
);

final _row = {
  'id': 5,
  'slug': 'ask-5',
  'price': 10000,
  'condition': 'NM',
  'quantity': 1,
  'qty_locked': 0,
  'user_id': 'u1',
  'created_at': '2026-10-01T00:00:00Z',
};

Future<void> _pump(
  WidgetTester tester, {
  required int score,
  SellerRating? rating,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SellerRatingBadge(score: score, rating: rating),
      ),
    ),
  );
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.me);
  final AppUser? me;
  @override
  Future<AppUser?> build() async => me;
}

ListingModel _listing({
  int id = 1,
  String sellerId = 'seller',
  String storeName = 'VSW',
  int price = 160000,
  bool acceptsOffers = false,
  int quantity = 1,
}) => ListingModel(
  id: id,
  slug: 'ask-$id',
  side: ListingSide.ask,
  price: price,
  condition: CardCondition.nm,
  quantity: quantity,
  card: _card,
  storeSlug: 'store-$id',
  storeName: storeName,
  isVerified: false,
  cityName: 'Kota Administrasi Jakarta Selatan',
  createdAt: DateTime(2026, 10, id),
  acceptsOffers: acceptsOffers,
  sellerId: sellerId,
  sellerFeedbackScore: 37,
  sellerRating: const SellerRating(totalSales: 29),
);

Future<void> _pumpSection(
  WidgetTester tester,
  List<ListingModel> listings, {
  AppUser? me,
}) async {
  tester.view.physicalSize = const Size(393, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(me)),
        cardListingsProvider(_card.id).overrideWith((ref) async => listings),
        myOfferOnListingProvider.overrideWith(
          (ref, slug) => const AsyncValue.data(null),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CardListingsSection(cardId: _card.id),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a listing row carries the seller city and reputation', () {
    final listing = cardListingFromRow(
      _row,
      card: _card,
      store: StoreIdentity.fromRow(const {
        'user_id': 'u1',
        'store_name': 'Takumie',
        'city_name': 'Kota Bandung',
      }),
      reputation: const {
        'positive_pct': 98.5,
        'successful_trades': 37,
        'positive_count_total': 40,
        'neutral_count_12mo': 1,
        'negative_count_total': 1,
      },
    );

    expect(listing.cityName, 'Kota Bandung');
    expect(listing.sellerRating!.positivePct, 98.5);
    expect(listing.sellerRating!.totalSales, 37);
  });

  test('an older backend without city_name leaves the city blank', () {
    final listing = cardListingFromRow(
      _row,
      card: _card,
      store: StoreIdentity.fromRow(const {'user_id': 'u1'}),
    );
    expect(listing.cityName, '');
    expect(listing.sellerRating, isNull);
  });

  testWidgets('rating line: star score and sales, no percent', (tester) async {
    await _pump(
      tester,
      score: 37,
      rating: const SellerRating(positivePct: 100, totalSales: 29),
    );
    expect(find.text('37'), findsOneWidget);
    expect(find.text(' · 29 penjualan'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('an unrated seller is "Penjual baru"', (tester) async {
    await _pump(tester, score: 0);
    expect(find.text('Penjual baru'), findsOneWidget);
  });

  testWidgets('a scored seller with no sales shows just the star', (
    tester,
  ) async {
    await _pump(tester, score: 12, rating: const SellerRating());
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('penjualan'), findsNothing);
  });

  testWidgets('row: full-width Keranjang, Tawar only when offers open', (
    tester,
  ) async {
    await _pumpSection(tester, [
      _listing(id: 1, acceptsOffers: true),
      _listing(id: 2, storeName: 'ZHITATCG', price: 165500),
    ]);
    expect(find.text('Keranjang'), findsNWidgets(2));
    expect(find.text('Tawar'), findsOneWidget);
    expect(find.byTooltip('Chat penjual'), findsNWidgets(2));
    expect(find.text('Kota Administrasi Jakarta Selatan'), findsNWidgets(2));
    expect(find.text(' · 29 penjualan'), findsNWidgets(2));
  });

  testWidgets('own listing hides chat and Tawar', (tester) async {
    await _pumpSection(tester, [
      _listing(acceptsOffers: true, sellerId: 'me'),
    ], me: const AppUser(id: 'me', email: 'me@example.com'));
    expect(find.byTooltip('Chat penjual'), findsNothing);
    expect(find.text('Tawar'), findsNothing);
    expect(find.text('Keranjang'), findsOneWidget);
  });

  testWidgets('a long name and a billion-rupiah price fit a 393pt phone', (
    tester,
  ) async {
    await _pumpSection(tester, [
      _listing(
        storeName: 'Kartu Langka Nusantara Official',
        price: 1250000000,
        acceptsOffers: true,
        quantity: 99,
      ),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Rp1.250.000.000'), findsOneWidget);
    expect(find.text('Kartu Langka Nusantara Official'), findsOneWidget);
  });
}
