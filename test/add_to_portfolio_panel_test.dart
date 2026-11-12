import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/providers/card_ownership_controller.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/add_to_portfolio_panel.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/market_models.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The panel that replaced the bare stepper under the artwork. Its job is to
/// say where a copy is going and in what condition, keep a running total
/// over every condition held, and write each tap straight away.
const _card = CardModel(
  id: 42,
  category: CardCategory.pokemon,
  nameId: 'Charizard ex',
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '201/165',
  rarity: 'SAR',
  variant: 'holofoil',
);

const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

/// Records what the panel asks for instead of talking to Supabase.
class _FakeOwnership implements CardOwnershipController {
  final adjustments = <int>[];
  final conditions = <CardCondition?>[];

  /// Held open by the test that needs to look at the panel mid-write, so the
  /// write can be finished on cue rather than resolving in the same tick.
  Completer<String?>? gate;

  @override
  Future<String?> adjustQuantity({
    required String userId,
    required int cardId,
    required int delta,
    String? listId,
    CardCondition? condition,
  }) async {
    adjustments.add(delta);
    conditions.add(condition);
    return gate?.future ?? Future.value(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A day of the year-long series, [daysAgo] before today.
MarketPricePoint _point(CardCondition condition, int daysAgo, int price) =>
    MarketPricePoint(
      condition: condition,
      day: DateTime(2026, 11, 12).subtract(Duration(days: daysAgo)),
      rawPrice: price,
    );

Future<_FakeOwnership> _pump(
  WidgetTester tester, {
  int owned = 0,
  Map<CardCondition, int>? held,
  List<MarketPricePoint> series = const [],
  CardMarketPrice? price = const CardMarketPrice(
    price: 125000,
    condition: CardCondition.nm,
    source: CardPriceSource.confirmed,
    price7dAgo: 100000,
  ),
}) async {
  final ownership = _FakeOwnership();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        cardOwnershipControllerProvider.overrideWithValue(ownership),
        // No saved lists, so the only portfolio is "Utama".
        listsProvider.overrideWith((ref) async => []),
        conditionQuantitiesProvider((
          listId: null,
          cardId: _card.id,
        )).overrideWith((ref) async => held ?? {CardCondition.nm: owned}),
        cardMarketPriceProvider(_card.id).overrideWith((ref) async => price),
        marketPriceSeriesProvider((
          cardId: _card.id,
          days: null,
        )).overrideWith((ref) async => series),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AddToPortfolioPanel(card: _card)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ownership;
}

void main() {
  testWidgets('says which portfolio a copy is going to', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Menambah ke'), findsOneWidget);
    expect(find.text('Utama'), findsOneWidget);
    // The row is labelled with the condition being counted.
    expect(find.text('Near Mint'), findsOneWidget);
  });

  testWidgets('the total follows the stepper before anything is written', (
    tester,
  ) async {
    await _pump(tester, owned: 1);

    expect(find.text('Total: Rp125.000'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();

    expect(find.text('Total: Rp250.000'), findsOneWidget);
  });

  testWidgets('a tap writes straight away, one copy at a time', (tester) async {
    // No debounce: a stepper that waits before writing has to look idle
    // while it waits, and that wait is exactly when the reader wonders
    // whether the tap registered.
    final ownership = await _pump(tester, owned: 0);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(ownership.adjustments, [1]);

    // Past the tick, which holds the button for a beat after the write.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(ownership.adjustments, [1, 1]);
  });

  testWidgets('the pressed button reports back, in green, with a tick', (
    tester,
  ) async {
    final ownership = await _pump(tester, owned: 0);
    ownership.gate = Completer<String?>();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();

    // Working: no spinner anywhere, and the sign is still its own button
    // rather than being replaced by one.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(LucideIcons.check), findsNothing);

    ownership.gate!.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Landed: the tick sits on the button that was pressed.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);

    // And it goes away on its own.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('the stepper is locked while the write is in flight', (
    tester,
  ) async {
    final ownership = await _pump(tester, owned: 0);
    ownership.gate = Completer<String?>();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump(const Duration(seconds: 1));

    // The write is away and hasn't come back: the count stays on screen and
    // further taps are dropped, both signs having gone dead.
    expect(ownership.adjustments, [1]);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump(const Duration(seconds: 1));
    expect(ownership.adjustments, [1]);
    expect(find.text('1'), findsOneWidget);

    // Once it lands the stepper is live again, counting from what the server
    // confirmed rather than from the tap that was refused.
    ownership.gate!.complete(null);
    await tester.pump();
    // Past the tick, which holds the button for a beat after the write.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump(const Duration(seconds: 1));
    expect(ownership.adjustments, [1, 1]);
  });

  testWidgets('the count holds until the refetch catches up', (tester) async {
    // Between a write landing and the provider re-resolving, the provider is
    // still reporting the count from before it. Re-seeding from that snapped
    // the number back to what the user had just changed it from.
    await _pump(tester, owned: 1);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Total: Rp250.000'), findsOneWidget);
  });

  testWidgets('the stepper counts and writes the condition picked', (
    tester,
  ) async {
    // 2x NM and 1x LP are two rows: switching to LP shows LP's own count,
    // and the next copy is filed as LP.
    final ownership = await _pump(
      tester,
      held: {CardCondition.nm: 2, CardCondition.lp: 1},
    );
    expect(find.text('Near Mint'), findsOneWidget);

    await tester.tap(find.text('Near Mint'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LP').last);
    await tester.pumpAndSettle();
    expect(find.text('Lightly Played'), findsOneWidget);
    // And the picker has folded away again.
    expect(find.text('RAW'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(ownership.adjustments, [1]);
    expect(ownership.conditions, [CardCondition.lp]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('the week\'s move is shown against the price', (tester) async {
    await _pump(tester);

    expect(find.text('Rp125.000'), findsOneWidget);
    expect(find.text('+Rp25.000 (25.0%)'), findsOneWidget);
  });

  testWidgets('an ask price states no move', (tester) async {
    // Same rule as the catalog tiles: only a price built from sales has a
    // week-on-week move worth drawing.
    await _pump(
      tester,
      price: const CardMarketPrice(
        price: 125000,
        condition: CardCondition.nm,
        source: CardPriceSource.ask,
        price7dAgo: 100000,
      ),
    );

    expect(find.textContaining('%'), findsNothing);
  });

  group('conditions', () {
    testWidgets('opens on the condition held most', (tester) async {
      await _pump(tester, held: {CardCondition.nm: 1, CardCondition.lp: 3});
      expect(find.text('Lightly Played'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('"Di koleksi" only once two conditions are held', (
      tester,
    ) async {
      await _pump(tester, held: {CardCondition.nm: 2});
      expect(find.text('Di koleksi'), findsNothing);

      await tester.tap(find.text('Near Mint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LP').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // NM ×2 and now LP ×1: the row shows both, in picker order.
      expect(find.text('Di koleksi'), findsOneWidget);
      expect(find.text('NM ×2'), findsOneWidget);
      expect(find.text('LP ×1'), findsOneWidget);

      // A pill picks its condition without opening the picker.
      await tester.tap(find.text('NM ×2'));
      await tester.pumpAndSettle();
      expect(find.text('Near Mint'), findsOneWidget);
      expect(find.text('RAW'), findsNothing);
    });

    testWidgets('each chip says how many are held', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, held: {CardCondition.nm: 2, CardCondition.dmg: 1});
      await tester.tap(find.text('Near Mint'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Near Mint, 2 di koleksi'), findsOneWidget);
      // Damaged copies are a condition of their own.
      expect(find.bySemanticsLabel('Damaged, 1 di koleksi'), findsOneWidget);
      expect(find.bySemanticsLabel('Lightly Played'), findsOneWidget);
      // Graded copies wait for the backend to take them.
      expect(find.text('GRADED'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the total is every condition at its own price', (
      tester,
    ) async {
      await _pump(
        tester,
        held: {CardCondition.nm: 2, CardCondition.lp: 1},
        series: [
          _point(CardCondition.nm, 7, 90000),
          _point(CardCondition.nm, 0, 100000),
          _point(CardCondition.lp, 0, 60000),
        ],
      );
      // 2 × Rp100.000 + 1 × Rp60.000.
      expect(find.text('Total: Rp260.000'), findsOneWidget);
      // The row's price is the condition's own, with its week.
      expect(find.text('Rp100.000'), findsOneWidget);
      expect(find.text('+Rp10.000 (11.1%)'), findsOneWidget);

      await tester.tap(find.text('LP ×1'));
      await tester.pumpAndSettle();
      expect(find.text('Rp60.000'), findsOneWidget);
      // Nothing a week back to measure LP's move from.
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('a condition nobody has sold is left out, and said so', (
      tester,
    ) async {
      await _pump(
        tester,
        held: {CardCondition.nm: 1, CardCondition.mp: 2},
        series: [_point(CardCondition.nm, 0, 100000)],
      );
      expect(find.text('Total: Rp100.000'), findsOneWidget);
      expect(find.text('1 kondisi belum ada harga'), findsOneWidget);

      await tester.tap(find.text('MP ×2'));
      await tester.pumpAndSettle();
      expect(find.text('Rp–'), findsOneWidget);
    });

    testWidgets('no switching condition while a count is being written', (
      tester,
    ) async {
      final ownership = await _pump(
        tester,
        held: {CardCondition.nm: 2, CardCondition.lp: 1},
      );
      ownership.gate = Completer<String?>();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.tap(find.text('LP ×1'));
      await tester.pump();
      expect(find.text('Near Mint'), findsOneWidget);

      ownership.gate!.complete(null);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LP ×1'));
      await tester.pumpAndSettle();
      expect(find.text('Lightly Played'), findsOneWidget);
    });
  });

  group('prices by condition', () {
    test('the last price, and the one a week before it', () {
      final prices = ConditionPrice.fromSeries([
        _point(CardCondition.nm, 10, 80000),
        _point(CardCondition.nm, 7, 90000),
        _point(CardCondition.nm, 3, 95000),
        _point(CardCondition.nm, 0, 100000),
        _point(CardCondition.psa10, 0, 800000),
      ]);
      expect(prices[CardCondition.nm]!.price, 100000);
      expect(prices[CardCondition.nm]!.price7dAgo, 90000);
      expect(prices[CardCondition.psa10]!.price, 800000);
      expect(prices[CardCondition.psa10]!.price7dAgo, isNull);
      expect(prices.containsKey(CardCondition.lp), isFalse);
    });

    test('the EWMA when there is one, as the chart draws it', () {
      final prices = ConditionPrice.fromSeries([
        MarketPricePoint(
          condition: CardCondition.nm,
          day: DateTime(2026, 11, 12),
          rawPrice: 100000,
          avgPrice: 97000,
        ),
      ]);
      expect(prices[CardCondition.nm]!.price, 97000);
    });
  });
}
