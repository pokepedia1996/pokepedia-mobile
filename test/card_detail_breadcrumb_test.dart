import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/card_detail_page.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';
import 'package:pokepedia_mobile/shared/widgets/cart_app_bar_button.dart';

/// The card page opened straight onto artwork, with nothing saying which
/// expansion the card came from or how to get back to it.
const _card = CardModel(
  id: 42,
  category: CardCategory.pokemon,
  nameId: 'Charizard ex',
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '201/165',
  rarity: 'SAR',
);

const _pack = PackModel(
  slug: 'sv2a',
  name: 'Mega Evolution Promos',
  mark: 'SV2a',
  series: 'Scarlet & Violet',
  releaseDate: '2026-01-01',
  cardCount: 165,
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

class _EmptyCart implements CartRepository {
  @override
  Future<List<CartItem>> fetchCart() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _pump(WidgetTester tester, {PackModel? pack}) async {
  // Wide: the harness's square fallback font overflows this page's rows at
  // phone widths, for reasons unrelated to the breadcrumb.
  tester.view.physicalSize = const Size(2000, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        cartRepositoryProvider.overrideWithValue(_EmptyCart()),
        cardDetailProvider(42).overrideWith((ref) async => _card),
        packForCardProvider((
          slug: 'sv2a',
          language: 'id',
        )).overrideWith((ref) async => pack),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const CardDetailPage(packSlug: 'sv2a', cardId: 42),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the trail names the expansion, the card and its number', (
    tester,
  ) async {
    await _pump(tester, pack: _pack);

    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    expect(find.text('Charizard ex'), findsWidgets);
    expect(find.text('201/165'), findsWidgets);
  });

  testWidgets('the expansion falls back to its code while the pack loads', (
    tester,
  ) async {
    await _pump(tester, pack: null);

    // The code, uppercased — not a gap where the name will be.
    expect(find.text('SV2A'), findsOneWidget);
  });

  testWidgets('the bar carries the cart', (tester) async {
    await _pump(tester, pack: _pack);

    expect(find.byType(CartAppBarButton), findsOneWidget);
  });
}
