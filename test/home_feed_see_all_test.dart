import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/marketplace_feed_section.dart';
import 'package:pokepedia_mobile/features/home/usecase/home_feed_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

ListingModel _listing(int i) => ListingModel(
  id: i,
  sellerId: 's',
  slug: 'l$i',
  side: ListingSide.ask,
  price: 385000,
  condition: CardCondition.nm,
  quantity: 3,
  acceptsOffers: false,
  card: CardModel(
    id: i,
    category: CardCategory.pokemon,
    nameId: 'Kartu $i',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '038/165',
    rarity: 'Rare',
  ),
  storeSlug: 'toko',
  storeName: 'Toko Ash',
  isVerified: true,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 8, 1),
);

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<List<ListingModel>> feed,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        seriesGroupsProvider.overrideWith((ref) async => []),
        homeFeedProvider.overrideWith(
          (ref) => feed.when(
            data: (l) => Future.value(l),
            loading: () => Completer<List<ListingModel>>().future,
            error: (e, _) => Future<List<ListingModel>>.error(e),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(child: MarketplaceFeedSection()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// "Lihat semua" sat in the corner of the heading, above the listings it
/// applies to — so the moment it is wanted, having read to the end of the
/// feed, it is off-screen behind a scroll back up.
void main() {
  testWidgets('sits below the grid, spanning its width', (tester) async {
    await _pump(
      tester,
      AsyncValue.data([for (var i = 1; i <= 4; i++) _listing(i)]),
    );
    await tester.pumpAndSettle();

    final cta = find.text('Lihat semua');
    expect(cta, findsOneWidget);
    // A button, not the bare link the heading used to carry.
    expect(find.byType(OutlinedButton), findsOneWidget);

    final heading = tester.getRect(find.text('Marketplace'));
    final grid = tester.getRect(find.byType(GridView));
    final button = tester.getRect(cta);

    expect(button.top, greaterThan(heading.bottom));
    expect(button.top, greaterThanOrEqualTo(grid.bottom));

    // Centred in the section, not pushed to either edge. Measured on the
    // button rather than its label: the arrow beside the words is part of
    // what is being centred, so the text alone sits left of middle.
    final target = tester.getRect(find.byType(OutlinedButton));
    final section = tester.getRect(find.byType(MarketplaceFeedSection));
    expect(target.center.dx, closeTo(section.center.dx, 1));
    // Full width, inside the section's own 16pt gutters.
    expect(target.width, closeTo(section.width - 32, 0.5));
  });

  testWidgets('waits for the feed rather than floating over a spinner', (
    tester,
  ) async {
    await _pump(tester, const AsyncValue<List<ListingModel>>.loading());
    await tester.pump();

    expect(find.text('Lihat semua'), findsNothing);
  });

  testWidgets('a failed feed still offers the way out', (tester) async {
    await _pump(tester, AsyncValue.error('boom', StackTrace.empty));
    await tester.pumpAndSettle();

    expect(find.text('Lihat semua'), findsOneWidget);
  });
}
