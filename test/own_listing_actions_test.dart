import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/market/presentation/store_card_listing_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

/// A seller opening their own product page was offered "Hubungi" — a chat
/// with themselves — and "Ikuti", which `follow_shop` refuses outright.
const _seller = AppUser(id: 'seller', email: 'seller@example.com');
const _shopper = AppUser(id: 'shopper', email: 'shopper@example.com');

const _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 1,
  cityName: 'Jakarta',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 0,
  followersCount: 3,
  userId: 'seller',
);

final _listing = ListingModel(
  id: 1,
  sellerId: 'seller',
  slug: 'listing-1',
  side: ListingSide.ask,
  price: 125000,
  condition: CardCondition.nm,
  quantity: 2,
  card: const CardModel(
    id: 42,
    category: CardCategory.pokemon,
    nameId: 'Charizard ex',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '201/165',
    rarity: 'SAR',
  ),
  storeSlug: 'toko-ash',
  storeName: 'Toko Ash',
  isVerified: false,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 9, 1),
);

/// The app bar's cart badge builds the cart, which would otherwise reach for
/// an uninitialised Supabase.
class _EmptyCart implements CartRepository {
  @override
  Future<List<CartItem>> fetchCart() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

Future<void> _pump(WidgetTester tester, AppUser viewer) async {
  // Wide on purpose — the harness's square fallback font overflows this
  // page's rows at phone widths for reasons unrelated to what's under test.
  tester.view.physicalSize = const Size(2000, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(viewer)),
        storeCardListingsProvider((
          storeSlug: 'toko-ash',
          cardId: 42,
        )).overrideWith(
          (ref) async => (
            store: _store,
            listings: [_listing],
            otherSellersCount: 0,
            positivePct: 100.0,
            feedbackScore: 4,
          ),
        ),
        isFollowingShopProvider('seller').overrideWith((ref) async => false),
        myOffersProvider.overrideWith((ref) async => []),
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        cartRepositoryProvider.overrideWithValue(_EmptyCart()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const StoreCardListingPage(storeSlug: 'toko-ash', cardId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a shopper can contact and follow the seller', (tester) async {
    await _pump(tester, _shopper);

    expect(find.text('Hubungi'), findsOneWidget);
    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
  });

  testWidgets('the seller gets neither on their own listing', (tester) async {
    await _pump(tester, _seller);

    expect(find.text('Hubungi'), findsNothing);
    expect(find.text('Ikuti'), findsNothing);
    // Sharing your own listing still means something.
    expect(find.text('Bagikan'), findsOneWidget);
  });
}
