import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_products_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';

/// Every listing search is a round trip and a reload of the list, so the
/// box waits for typing to pause instead of searching on each keystroke.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'me', email: 'me@example.com');
}

Future<List<String>> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final searched = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        sellerBucketProvider.overrideWith((ref) => SellerListingBucket.active),
        sellerListingsPageProvider.overrideWith((ref) async {
          searched.add(ref.watch(sellerListingQueryProvider));
          return const SellerListingsPage();
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SellerProductsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  searched.clear();
  return searched;
}

Finder get _listingSearch =>
    find.widgetWithText(TextField, 'Cari nama, ekspansi, nomor, kondisi...');

void main() {
  testWidgets('typing searches once, after the pause', (tester) async {
    final searched = await _open(tester);

    for (final text in ['c', 'ch', 'cha', 'char']) {
      await tester.enterText(_listingSearch, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(searched, isEmpty, reason: 'still typing');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(searched, ['char']);
  });

  testWidgets('clearing the box searches at once', (tester) async {
    final searched = await _open(tester);

    await tester.enterText(_listingSearch, 'char');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    searched.clear();

    await tester.enterText(_listingSearch, '');
    await tester.pump();
    expect(searched, ['']);
  });

  testWidgets('a trailing space is not a new search', (tester) async {
    final searched = await _open(tester);

    await tester.enterText(_listingSearch, 'char');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    searched.clear();

    await tester.enterText(_listingSearch, 'char ');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(searched, isEmpty);
  });
}
