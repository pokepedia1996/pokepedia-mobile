import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/top_holdings_section.dart';
import 'package:pokepedia_mobile/features/home/repository/models/portfolio_value.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/shared/widgets/card_art.dart';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'u1', email: 'ash@pokepedia.id');
}

PortfolioHolding _holding({int quantity = 10, double? changePct}) =>
    PortfolioHolding(
      cardId: 1,
      name: 'Garchomp & Giratina GX',
      collectorNumber: '228/205',
      expansionCode: 'AC3A',
      rarity: 'SR',
      packSlug: 'ac3a',
      quantity: quantity,
      unitPrice: 6000000,
      imageUrl: 'https://example.invalid/card.webp',
      priceChangePct: changePct,
    );

Widget _host(List<PortfolioHolding> holdings) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: TopHoldingsSection()),
      ),
      GoRoute(path: Routes.portfolio, builder: (_, __) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioHoldingsProvider.overrideWith((ref) async => holdings),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('shows quantity as Xpcs and drops the card image', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_holding()]));
    await tester.pumpAndSettle();

    expect(find.text('10pcs'), findsOneWidget);
    // The artwork is gone — the row is a ledger line, not a gallery.
    expect(find.byType(CardArt), findsNothing);
    // And the old "×10" it replaced.
    expect(find.text('×10'), findsNothing);
  });

  testWidgets('shows the week move in place of the owned count', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_holding(changePct: 12.34)]));
    await tester.pumpAndSettle();

    expect(find.text('+12.3%'), findsOneWidget);
  });

  testWidgets('signs a fall and still shows the count', (tester) async {
    await tester.pumpWidget(_host([_holding(quantity: 2, changePct: -8.5)]));
    await tester.pumpAndSettle();

    expect(find.text('-8.5%'), findsOneWidget);
    expect(find.text('2pcs'), findsOneWidget);
  });

  testWidgets('says nothing when there is no confirmed price to compare', (
    tester,
  ) async {
    // An ask or a bid is one person's number; a trend through it would be
    // invented, so `priceChangePct` is null and the row stays silent.
    await tester.pumpWidget(_host([_holding()]));
    await tester.pumpAndSettle();

    expect(find.textContaining('%'), findsNothing);
  });
}
