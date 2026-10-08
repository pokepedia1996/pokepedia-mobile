import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/market/presentation/store_detail_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/cart_app_bar_button.dart';

/// A seller browsing their own storefront was offered both a Follow button
/// that `follow_shop` refuses (`cannot_follow_self`) and a Chat button with
/// nobody on the other end.
const _seller = AppUser(id: 'seller', email: 'seller@example.com');
const _shopper = AppUser(id: 'shopper', email: 'shopper@example.com');

final _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 1696,
  cityName: 'Kota Jakarta Barat',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 1,
  followersCount: 3,
  userId: 'seller',
  memberSince: DateTime(2026, 7, 1),
);

/// The bar's cart badge builds the cart, which would otherwise reach for an
/// uninitialised Supabase.
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

Future<void> _pump(WidgetTester tester, AppUser? viewer) async {
  // Wide on purpose: `flutter_test`'s square fallback font makes this
  // header's rows measure far wider than they do on a device, and the
  // overflow that causes has nothing to do with what's under test.
  tester.view.physicalSize = const Size(2000, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(viewer)),
        storeDetailProvider('toko-ash').overrideWith((ref) async => _store),
        storeListingsProvider('toko-ash').overrideWith((ref) async => []),
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        cartRepositoryProvider.overrideWithValue(_EmptyCart()),
        // The header's "N listing" loads on its own, beside the first page.
        storeListingCountProvider('seller').overrideWith((ref) async => 1696),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const StoreDetailPage(handle: 'toko-ash'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bar carries the cart', (tester) async {
    await _pump(tester, _shopper);

    expect(find.byType(CartAppBarButton), findsOneWidget);
  });

  testWidgets('the stats read as counts, then facts', (tester) async {
    await _pump(tester, _shopper);

    // Grouped rather than run together: "1696" was unreadable at a glance.
    expect(find.text('1.696'), findsOneWidget);
    expect(find.text('listing'), findsOneWidget);
    expect(find.text('terjual'), findsOneWidget);
    expect(find.text('pengikut'), findsOneWidget);

    // The city and the joining date sit below the counts, not wrapped in
    // among them.
    final counts = tester.getTopLeft(find.text('listing')).dy;
    final city = tester.getTopLeft(find.text('Kota Jakarta Barat')).dy;
    expect(city, greaterThan(counts));
  });

  testWidgets('a shopper gets follow, chat and share', (tester) async {
    await _pump(tester, _shopper);

    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('the seller gets neither on their own storefront', (
    tester,
  ) async {
    await _pump(tester, _seller);

    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Diikuti'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    // Sharing your own shop is the one action that still means something.
    expect(find.text('Bagikan toko'), findsOneWidget);
  });

  testWidgets('a guest still gets both, and is asked to sign in on tap', (
    tester,
  ) async {
    // Signed out is not the same as "this is mine": the buttons stay.
    await _pump(tester, null);

    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });
}
