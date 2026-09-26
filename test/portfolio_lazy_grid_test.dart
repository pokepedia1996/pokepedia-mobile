import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/portfolio_page.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';

/// The collection grid hands the sliver a window rather than the whole
/// collection: the child count is the ceiling on how many images one fling
/// can ask for, so a few thousand cards used to open a few thousand requests.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

CardModel _card(int id) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Kartu $id',
  expansionCode: 'SV3',
  packSlug: 'sv3',
  collectorNumber: '$id/197',
  rarity: 'SAR',
  owned: 1,
);

Future<void> _open(WidgetTester tester, {required int cards}) async {
  // A tall, narrowish surface, so a grid row is a few hundred pixels rather
  // than the ~600 the default 800x600 gives — the point here is how many
  // rows a scroll passes. Wider than a real phone only because the test
  // harness's square fallback font runs a tile's caption row over the edge
  // at phone widths.
  tester.view.physicalSize = const Size(500 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      listsProvider.overrideWith((ref) async => const []),
      collectionProvider.overrideWith(
        (ref) async => [for (var i = 1; i <= cards; i++) _card(i)],
      ),
      portfolioValueSeriesProvider.overrideWith((ref) async => const []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const PortfolioPage()),
    ),
  );
  // Not `pumpAndSettle`: the page's loader animates forever, so settling is
  // never reached. A couple of frames is all the providers need.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a long collection is handed to the grid a page at a time', (
    tester,
  ) async {
    await _open(tester, cards: 400);

    // Far short of the 400 owned — the window, not the collection, is what
    // the sliver was given. (Only the tiles inside the viewport plus its
    // cache extent are built, which is fewer still.)
    final first = tester.widgetList<CardGridItem>(find.byType(CardGridItem));
    expect(first.length, lessThan(40));
    expect(first, isNotEmpty);
  });

  testWidgets('scrolling towards the end reveals the next page', (
    tester,
  ) async {
    await _open(tester, cards: 400);

    // Every card the scroll passes. The window starts at 36, so passing more
    // than that many distinct cards is only possible if it grew on the way.
    final seen = <int>{};
    void record() => seen.addAll(
      tester
          .widgetList<CardGridItem>(find.byType(CardGridItem))
          .map((t) => t.card.id),
    );

    record();
    expect(seen.length, lessThanOrEqualTo(36));

    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 300));
      record();
    }

    expect(seen.length, greaterThan(36));
  });
}
