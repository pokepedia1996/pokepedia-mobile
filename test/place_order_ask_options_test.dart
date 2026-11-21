import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/place_order_sheet.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/trading_models.dart';
import 'package:pokepedia_mobile/features/expansions/repository/trading_repository.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/trading_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

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

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'seller', email: 'seller@example.com');
}

/// Records what the sheet sends, and answers with a failure so the sheet
/// stays open instead of moving on to the share prompt.
class _Repo implements TradingRepository {
  bool? autoRelist;
  bool? acceptsOffers;

  @override
  Future<PlaceOrderResult> placeOrder({
    required int cardId,
    required String side,
    required int price,
    required CardCondition condition,
    required int quantity,
    String? variantKey,
    bool replace = false,
    bool autoRelist = false,
    bool acceptsOffers = false,
    List<String> photoUrls = const [],
  }) async {
    this.autoRelist = autoRelist;
    this.acceptsOffers = acceptsOffers;
    return const PlaceOrderResult.failed('test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _open(
  WidgetTester tester,
  _Repo repo, {
  required String side,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        tradeEligibilityProvider.overrideWith(
          (ref) async => const TradeEligibility(
            phoneVerified: true,
            sellerActive: true,
            hasCouriers: true,
          ),
        ),
        tradingRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaceOrderSheet(
                context,
                card: _card,
                side: side,
                bestPrice: 50000,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an ask offers both options, off by default', (tester) async {
    final repo = _Repo();
    await _open(tester, repo, side: 'ask');

    expect(find.text('Terima penawaran'), findsOneWidget);
    expect(find.text('Perpanjang otomatis'), findsOneWidget);

    await tester.tap(find.text('Pasang Ask'));
    await tester.pumpAndSettle();
    expect(repo.acceptsOffers, isFalse);
    expect(repo.autoRelist, isFalse);
  });

  testWidgets('ticking them sends them with the ask', (tester) async {
    final repo = _Repo();
    await _open(tester, repo, side: 'ask');

    await tester.tap(find.text('Terima penawaran'));
    await tester.tap(find.text('Perpanjang otomatis'));
    await tester.pump();
    await tester.tap(find.text('Pasang Ask'));
    await tester.pumpAndSettle();

    expect(repo.acceptsOffers, isTrue);
    expect(repo.autoRelist, isTrue);
  });

  testWidgets('a bid shows neither', (tester) async {
    await _open(tester, _Repo(), side: 'bid');

    expect(find.text('Pasang Bid (WTB)'), findsOneWidget);
    expect(find.text('Terima penawaran'), findsNothing);
    expect(find.text('Perpanjang otomatis'), findsNothing);
  });
}
