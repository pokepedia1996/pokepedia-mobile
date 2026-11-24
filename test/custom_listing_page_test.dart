import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/market/presentation/custom_listing_page.dart';
import 'package:pokepedia_mobile/features/market/repository/models/custom_listing_detail.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/condition_badge.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

const _seller = AppUser(id: 'seller', email: 'seller@example.com');
const _buyer = AppUser(id: 'buyer', email: 'buyer@example.com');

final _store = StoreModel(
  handle: 'toko-user1',
  storeName: 'Toko User1',
  tagline: '',
  activeListingCount: 3,
  cityName: 'Kota Jakarta Selatan',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 1,
  followersCount: 3,
  userId: 'seller',
  memberSince: DateTime(2026, 7, 1),
);

CustomListingDetail _detail({
  bool isLive = true,
  String status = 'open',
  bool acceptsOffers = true,
  String? description = 'Isi paket: 2 kartu, sleeve baru.',
  List<CustomTaggedCard>? tags,
}) => CustomListingDetail(
  id: 7,
  slug: 'custom-slug',
  sellerId: 'seller',
  title: 'Paket Charizard & Pikachu',
  description: description,
  price: 2900000,
  quantity: 3,
  qtyLocked: 1,
  photoUrls: const [],
  status: status,
  acceptsOffers: acceptsOffers,
  isLive: isLive,
  createdAt: DateTime(2026, 11, 23),
  tags:
      tags ??
      const [
        CustomTaggedCard(
          cardId: 42,
          name: 'Charizard ex',
          condition: CardCondition.nm,
          quantity: 1,
          expansionCode: 'SV3',
          collectorNumber: '125/197',
          language: CardLanguage.id,
        ),
        CustomTaggedCard(
          cardId: 0,
          name: 'Kartu tanpa halaman',
          condition: CardCondition.nm,
          quantity: 2,
          expansionCode: '',
          collectorNumber: '',
          language: CardLanguage.id,
        ),
      ],
);

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

/// The cart badge in the app bar builds the cart, which would otherwise
/// reach for an uninitialised Supabase.
class _Cart implements CartRepository {
  final added = <(int, int)>[];

  @override
  RealtimeChannel? subscribeToCart(void Function() onChange) => null;

  @override
  Future<List<CartItem>> fetchCart() async => const [];

  @override
  Future<void> add(int listingId, int quantity) async =>
      added.add((listingId, quantity));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<_Cart> _pump(
  WidgetTester tester, {
  required AppUser? viewer,
  CustomListingData? data,
  bool hasListing = true,
}) async {
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final cart = _Cart();
  final resolved =
      data ??
      (hasListing
          ? (
              detail: _detail(),
              store: _store,
              listing: _detail().toListing(_store),
            )
          : null);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const CustomListingPage(
          storeSlug: 'toko-user1',
          listingSlug: 'custom-slug',
        ),
      ),
      GoRoute(
        path: '/expansions/:packSlug/:cardId',
        builder: (_, state) => Text(
          'card ${state.pathParameters['packSlug']} '
          '${state.pathParameters['cardId']}',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(viewer)),
        customListingProvider((
          storeSlug: 'toko-user1',
          slug: 'custom-slug',
        )).overrideWith((ref) async => resolved),
        myOffersProvider.overrideWith((ref) async => []),
        isFollowingShopProvider('seller').overrideWith((ref) async => false),
        cartRepositoryProvider.overrideWithValue(cart),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return cart;
}

void main() {
  testWidgets('shows the seller\'s title, price, description and cards', (
    tester,
  ) async {
    await _pump(tester, viewer: _buyer);

    expect(find.text('Paket Charizard & Pikachu'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.textContaining('2.900.000'), findsWidgets);
    expect(find.text('2 tersedia'), findsOneWidget);
    expect(find.text('Isi paket: 2 kartu, sleeve baru.'), findsOneWidget);
    expect(find.text('Kartu di listing ini'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Toko User1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('has no grade of its own, only the tagged cards do', (
    tester,
  ) async {
    await _pump(tester, viewer: _buyer);

    // One badge per tagged card, none for the listing itself.
    expect(find.byType(ConditionBadge), findsNWidgets(2));
    expect(find.text('Lihat semua listing kartu ini'), findsNothing);
  });

  testWidgets('a buyer can add to the cart and make an offer', (tester) async {
    final cart = await _pump(tester, viewer: _buyer);

    expect(find.text('Keranjang'), findsOneWidget);
    expect(find.text('Tawar'), findsOneWidget);

    await tester.tap(find.text('Keranjang'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(cart.added, [(7, 1)]);
  });

  testWidgets('no offer button when the seller takes none', (tester) async {
    await _pump(
      tester,
      viewer: _buyer,
      data: (
        detail: _detail(acceptsOffers: false),
        store: _store,
        listing: _detail(acceptsOffers: false).toListing(_store),
      ),
    );

    expect(find.text('Tawar'), findsNothing);
    expect(find.text('Keranjang'), findsOneWidget);
  });

  testWidgets('the owner manages the listing instead of buying it', (
    tester,
  ) async {
    await _pump(tester, viewer: _seller);

    expect(find.text('Kelola listing'), findsOneWidget);
    expect(find.text('Keranjang'), findsNothing);
    expect(find.text('Tawar'), findsNothing);
  });

  testWidgets('an unpublished listing says so to its owner', (tester) async {
    await _pump(
      tester,
      viewer: _seller,
      data: (
        detail: _detail(isLive: false, status: 'draft'),
        store: _store,
        listing: _detail(isLive: false, status: 'draft').toListing(_store),
      ),
    );

    expect(find.textContaining('Draft'), findsOneWidget);
  });

  testWidgets('a buyer cannot add an expired listing to the cart', (
    tester,
  ) async {
    await _pump(
      tester,
      viewer: _buyer,
      data: (
        detail: _detail(isLive: false),
        store: _store,
        listing: _detail(isLive: false).toListing(_store),
      ),
    );

    expect(find.text('0 tersedia'), findsOneWidget);
    expect(find.text('Tawar'), findsNothing);
    final cart = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Keranjang'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(cart.onPressed, isNull);
  });

  testWidgets('a sold-out listing offers nothing to buy', (tester) async {
    final soldOut = CustomListingDetail(
      id: 7,
      slug: 'custom-slug',
      sellerId: 'seller',
      title: 'Paket Charizard & Pikachu',
      price: 2900000,
      quantity: 3,
      qtyLocked: 3,
      photoUrls: const [],
      status: 'open',
      acceptsOffers: true,
      isLive: true,
      createdAt: DateTime(2026, 11, 23),
    );
    await _pump(
      tester,
      viewer: _buyer,
      data: (
        detail: soldOut,
        store: _store,
        listing: soldOut.toListing(_store),
      ),
    );

    expect(find.text('0 tersedia'), findsOneWidget);
    expect(find.text('Tawar'), findsNothing);
    final cart = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Keranjang'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(cart.onPressed, isNull);
  });

  testWidgets('a store on hard vacation cannot be bought from', (tester) async {
    final onVacation = StoreModel(
      handle: 'toko-user1',
      storeName: 'Toko User1',
      tagline: '',
      activeListingCount: 3,
      cityName: 'Kota Jakarta Selatan',
      isVerified: false,
      topRated: false,
      itemsSoldCount: 1,
      followersCount: 3,
      userId: 'seller',
      vacationMode: 'hard',
      memberSince: DateTime(2026, 7, 1),
    );
    await _pump(
      tester,
      viewer: _buyer,
      data: (
        detail: _detail(),
        store: onVacation,
        listing: _detail().toListing(onVacation),
      ),
    );

    expect(find.textContaining('Checkout tidak tersedia'), findsOneWidget);
    final cart = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Keranjang'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(cart.onPressed, isNull);
  });

  testWidgets('no description, no description block', (tester) async {
    await _pump(
      tester,
      viewer: _buyer,
      data: (
        detail: _detail(description: null),
        store: _store,
        listing: _detail(description: null).toListing(_store),
      ),
    );

    expect(find.text('Deskripsi'), findsNothing);
  });

  testWidgets('a tagged card opens its catalog page', (tester) async {
    await _pump(tester, viewer: _buyer);

    await tester.tap(find.text('Charizard ex'));
    await tester.pumpAndSettle();

    expect(find.text('card sv3 42'), findsOneWidget);
  });

  testWidgets('a listing the viewer can\'t see says it is gone', (
    tester,
  ) async {
    await _pump(tester, viewer: _buyer, hasListing: false);

    expect(find.text('Listing tidak lagi tersedia'), findsOneWidget);
    expect(find.text('Paket Charizard & Pikachu'), findsNothing);
  });
}
