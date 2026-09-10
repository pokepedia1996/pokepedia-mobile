import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/providers/card_ownership_controller.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/add_to_portfolio_panel.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The panel that replaced the bare stepper under the artwork. Its job is to
/// say where a copy is going, keep a running total, and write once when the
/// tapping stops — the last part is the one worth pinning down, since a
/// stepper that wrote per tap would cost five round trips to add five.
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

  /// Held open by the test that needs to look at the panel mid-write, so the
  /// write can be finished on cue rather than resolving in the same tick.
  Completer<String?>? gate;

  @override
  Future<String?> adjustQuantity({
    required String userId,
    required int cardId,
    required int delta,
    String? listId,
  }) async {
    adjustments.add(delta);
    return gate?.future ?? Future.value(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<_FakeOwnership> _pump(
  WidgetTester tester, {
  int owned = 0,
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
        ownedQuantityProvider(_card.id).overrideWith((ref) async => owned),
        cardMarketPriceProvider(_card.id).overrideWith((ref) async => price),
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
    // The variant is the row's label, spelled as a person would say it.
    expect(find.text('Holofoil'), findsOneWidget);
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
}
