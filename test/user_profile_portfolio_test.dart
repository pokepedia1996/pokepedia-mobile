import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/features/user/presentation/user_profile_page.dart';
import 'package:pokepedia_mobile/features/user/repository/models/profile_models.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';

/// A profile shows a portfolio now — the same priced grid the Koleksi page
/// draws — rather than a thumbnail strip per expansion. The visibility
/// switch is the only thing its owner still toggles.
const _owner = AppUser(id: 'owner', email: 'owner@example.com');
const _visitor = AppUser(id: 'visitor', email: 'visitor@example.com');

PublicProfile _profile({bool isPublic = true}) => PublicProfile(
  userId: 'owner',
  username: 'figaro89',
  isCollectionPublic: isPublic,
  showCollectionQuantity: true,
  contributionCount: 0,
);

CardModel _card({required int id, required String name, int price = 100000}) =>
    CardModel(
      id: id,
      category: CardCategory.pokemon,
      nameId: name,
      expansionCode: 'BS',
      packSlug: 'bs',
      collectorNumber: '00$id/102',
      rarity: 'Holo Rare',
      marketPrice: price,
      owned: 2,
    );

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

StoreModel _shop({int followers = 12}) => StoreModel(
  handle: 'figaro89',
  storeName: 'Toko Figaro',
  tagline: '',
  activeListingCount: 0,
  cityName: 'Jakarta',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 0,
  followersCount: followers,
  userId: 'owner',
);

Future<void> _pump(
  WidgetTester tester, {
  AppUser? viewer = _owner,
  bool isPublic = true,
  List<CardModel> collection = const [],
  StoreModel? shop,
  bool alreadyFollowing = false,
  ({String userId, int followers, int following})? stats,
}) async {
  // Wide on purpose: `flutter_test` draws text in a square fallback font, so
  // a phone-width grid overflows horizontally here for reasons that have
  // nothing to do with this page — the same caveat `card_grid_item_height_test`
  // carries.
  tester.view.physicalSize = const Size(1800, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(viewer)),
        userProfileProvider(
          'figaro89',
        ).overrideWith((ref) async => _profile(isPublic: isPublic)),
        userCollectionProvider(
          'figaro89',
        ).overrideWith((ref) async => collection),
        userContributionsProvider('figaro89').overrideWith((ref) async => []),
        profileShopProvider('figaro89').overrideWith((ref) async => shop),
        profileFollowStatsProvider(
          'figaro89',
        ).overrideWith((ref) async => stats),
        followedShopsProvider.overrideWith((ref) async => const []),
        if (shop?.userId != null)
          isFollowingShopProvider(
            shop!.userId!,
          ).overrideWith((ref) async => alreadyFollowing),
        seriesGroupsProvider.overrideWith((ref) async => []),
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const UserProfilePage(username: 'figaro89'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the collection is drawn as a valued portfolio', (tester) async {
    await _pump(
      tester,
      collection: [
        _card(id: 1, name: 'Charizard', price: 762000),
        _card(id: 2, name: 'Venusaur', price: 109000),
      ],
    );

    expect(find.text('Portofolio'), findsOneWidget);
    // 2 copies of each, so the total is twice the sum of the two prices.
    expect(find.text('Rp1.742.000'), findsOneWidget);
    expect(find.text('2 kartu unik · 4 total'), findsOneWidget);
    expect(find.byType(CardGridItem), findsNWidgets(2));
  });

  testWidgets('followers and following sit under the name', (tester) async {
    await _pump(tester, shop: _shop(followers: 12));

    expect(find.text('12'), findsOneWidget);
    expect(find.text('Pengikut'), findsOneWidget);
    // The owner's own following count is the one number that is knowable —
    // `shop_follows` is select-own.
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets('the stats RPC answers for a visitor too', (tester) async {
    // With `get_profile_follow_stats` deployed, both counts are readable for
    // anyone — the fallback path can only ever see your own following.
    await _pump(
      tester,
      viewer: _visitor,
      shop: _shop(followers: 12),
      stats: (userId: 'owner', followers: 40, following: 7),
    );

    expect(find.text('40'), findsOneWidget, reason: 'the RPC wins');
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Mengikuti'), findsOneWidget);
    expect(find.text('Pengikut'), findsOneWidget);
  });

  testWidgets('a visitor can follow a shop', (tester) async {
    await _pump(tester, viewer: _visitor, shop: _shop());

    expect(find.widgetWithText(ElevatedButton, 'Ikuti'), findsOneWidget);
    // The count isn't knowable for someone else without the RPC, but the
    // stat is still drawn — at zero.
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets('an already-followed shop offers to stop', (tester) async {
    await _pump(
      tester,
      viewer: _visitor,
      shop: _shop(),
      alreadyFollowing: true,
    );

    // "Diikuti" on the button, so it can't be mistaken for the "Mengikuti"
    // stat beside it — outlined once followed, filled before, the way the
    // storefront draws the same pair.
    expect(find.text('Diikuti'), findsOneWidget);
    expect(find.text('Ikuti'), findsNothing);
    expect(find.byType(OutlinedButton), findsWidgets);
    expect(
      find.widgetWithText(ElevatedButton, 'Diikuti'),
      findsNothing,
      reason: 'the followed state is the quiet one',
    );
  });

  testWidgets('a profile with no shop has nothing to follow', (tester) async {
    // `follow_shop` inserts nothing for a user without an active shop, so a
    // button here would be a lie.
    await _pump(tester, viewer: _visitor, shop: null);

    expect(find.text('Ikuti'), findsNothing);
    // The pair still shows, at zero — a profile that hides them reads as one
    // still loading.
    expect(find.text('Pengikut'), findsOneWidget);
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets('the owner gets one switch, for visibility', (tester) async {
    await _pump(tester, collection: [_card(id: 1, name: 'Charizard')]);

    expect(find.text('Koleksi Publik'), findsOneWidget);
    // The quantity toggle is gone; quantities are simply shown.
    expect(find.text('Jumlah'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('a visitor sees no switches at all', (tester) async {
    await _pump(
      tester,
      viewer: _visitor,
      collection: [_card(id: 1, name: 'Charizard')],
    );

    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CardGridItem), findsOneWidget);
  });

  testWidgets('a private collection stays shut to a visitor', (tester) async {
    await _pump(
      tester,
      viewer: _visitor,
      isPublic: false,
      collection: const [],
    );

    expect(find.text('Koleksi pengguna ini bersifat privat'), findsOneWidget);
    expect(find.byType(CardGridItem), findsNothing);
  });
}
