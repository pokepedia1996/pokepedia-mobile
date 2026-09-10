import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/widgets/listing_card.dart';

/// `listingGridDelegate` sizes its cells from two measured constants. If the
/// card grows a row and nobody updates them, every market grid overflows.
/// These tests are what make that a failing build instead.
///
/// Only wide cells are checked. `flutter_test` draws text in a fallback font
/// whose glyphs are square, so strings measure far wider than they do on a
/// device; below ~170pt that fake width overflows the card horizontally and
/// swamps the vertical measurement this is actually about.
ListingModel _listing() => ListingModel(
  id: 1,
  sellerId: 's',
  slug: 'l',
  side: ListingSide.ask,
  price: 385000,
  condition: CardCondition.nm,
  quantity: 3,
  card: const CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Professor Elm Training Method',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '038/165',
    rarity: 'Rare',
  ),
  storeSlug: 'toko',
  storeName: 'Toko Ash',
  isVerified: true,
  cityName: 'Kota Jakarta Selatan',
  createdAt: DateTime(2026, 8, 1),
);

Future<bool> _overflows(
  WidgetTester tester,
  double width,
  double height, {
  required bool showSeller,
}) async {
  // A blank frame first: pumping the identical tree twice repaints nothing,
  // so no fresh overflow error is reported and every size after the first
  // looks fine.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.takeException();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        seriesGroupsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: ListingCard(listing: _listing(), showSeller: showSeller),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.takeException() != null;
}

/// What `listingGridDelegate` would give a cell this wide.
double _extentFor(double cellWidth, {required bool showSeller}) =>
    (cellWidth - 16) * 342 / 245 +
    (showSeller ? listingCardChrome : listingCardChromeNoSeller);

void main() {
  testWidgets('the seller strip names the shop before it rates it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // A tile whose seller footer showed only a tick, a star and a city was
    // the one thing on it that never said who was selling.
    await _overflows(
      tester,
      260,
      _extentFor(260, showSeller: true),
      showSeller: true,
    );

    expect(find.text('Toko Ash'), findsOneWidget);
    expect(find.text('Kota Jakarta Selatan'), findsOneWidget);

    final name = tester.getTopLeft(find.text('Toko Ash'));
    final tick = tester.getTopLeft(find.byIcon(LucideIcons.badgeCheck));
    expect(name.dx, lessThan(tick.dx), reason: 'the name leads the badges');
    expect(
      name.dy,
      lessThan(tester.getTopLeft(find.text('Kota Jakarta Selatan')).dy),
    );
  });

  testWidgets('the harness can see an overflow at all', (tester) async {
    // Without this the numbers below would be meaningless: a harness that
    // never reports overflow reports every height as fine.
    expect(
      await _overflows(tester, 173, 60, showSeller: true),
      isTrue,
      reason: '60pt must overflow — the artwork alone is taller',
    );
  });

  for (final showSeller in [true, false]) {
    testWidgets('the computed cell fits a card (showSeller: $showSeller)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (final cell in [173.0, 210.0, 260.0]) {
        final extent = _extentFor(cell, showSeller: showSeller);
        expect(
          await _overflows(tester, cell, extent, showSeller: showSeller),
          isFalse,
          reason: 'cell ${cell}x$extent overflows with showSeller=$showSeller',
        );
      }
    });
  }
}
