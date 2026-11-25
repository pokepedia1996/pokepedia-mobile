import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/portfolio_value_section.dart';
import 'package:pokepedia_mobile/features/home/repository/models/portfolio_value.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/collection_page.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Beranda's portfolio card: shut on the figure and its move, open on the
/// chart and the top holdings, and the eye hiding every rupiah on it.
class _SignedIn extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'me', email: 'me@example.com');
}

PortfolioHolding _holding(String name, int price, {double? change}) =>
    PortfolioHolding(
      cardId: name.length,
      name: name,
      collectorNumber: '137/103',
      expansionCode: 'ma2',
      rarity: 'SAR',
      packSlug: 'ma2',
      quantity: 1,
      unitPrice: price,
      priceChangePct: change,
      language: CardLanguage.jp,
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_SignedIn.new),
        collectionSummaryProvider.overrideWith(
          (ref) async => const CollectionSummary(
            totalValue: 3600000,
            uniqueCount: 3,
            totalCount: 3,
            valueNow: 3600000,
            value7dAgo: 4000000,
          ),
        ),
        portfolioValueSeriesProvider.overrideWith(
          (ref) async => [
            PortfolioValuePoint(
              day: DateTime.utc(2026, 11, 13),
              value: 4000000,
            ),
            PortfolioValuePoint(
              day: DateTime.utc(2026, 11, 19),
              value: 3600000,
            ),
          ],
        ),
        portfolioHoldingsProvider.overrideWith(
          (ref) async => [
            _holding('Tauros', 96000, change: 0),
            _holding('Mega Charizard X ex', 2618499, change: -2.94),
            _holding('Pikachu ex', 412000, change: 1.8),
            _holding('Bulbasaur', 1000),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PortfolioValueSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shut: the portfolio, its value and the move', (tester) async {
    await _pump(tester);

    expect(find.text('Portofolio Utama'), findsOneWidget);
    expect(find.text('Rp3.600.000'), findsOneWidget);
    expect(find.text('−Rp400.000 (10,0%)'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trendingDown), findsOneWidget);
    // The chart and holdings wait for the toggle.
    expect(find.text('7H'), findsNothing);
    expect(find.text('Nilai tertinggi'), findsNothing);
  });

  testWidgets('open: the range switch and the three biggest holdings', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byIcon(LucideIcons.chevronDown).last);
    await tester.pumpAndSettle();

    expect(find.text('7H'), findsOneWidget);
    expect(find.text('MAX'), findsOneWidget);
    expect(find.text('Nilai tertinggi'), findsOneWidget);
    expect(find.text('Lihat semua'), findsOneWidget);

    // Biggest first, three of them, priced a copy.
    final names = ['Mega Charizard X ex', 'Pikachu ex', 'Tauros'];
    final tops = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('Bulbasaur'), findsNothing);
    expect(find.text('Rp2.618.499'), findsOneWidget);
    expect(find.text('−2,9%'), findsOneWidget);
    expect(find.text('+1,8%'), findsOneWidget);
    expect(find.text('+0,0%'), findsOneWidget);
    expect(find.text('137/103 · MA2 · SAR'), findsNWidgets(3));

    await tester.tap(find.byIcon(LucideIcons.chevronUp));
    await tester.pumpAndSettle();
    expect(find.text('Nilai tertinggi'), findsNothing);
  });

  testWidgets('the eye hides every rupiah figure, and remembers', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byIcon(LucideIcons.chevronDown).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();

    expect(find.text('Rp3.600.000'), findsNothing);
    expect(find.text('Rp•••••••'), findsOneWidget);
    // The move keeps its direction and size, not its amount.
    expect(find.text('−10,0%'), findsOneWidget);
    expect(find.text('Rp2.618.499'), findsNothing);
    expect(find.text('Rp•••'), findsNWidgets(3));
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pokepedia.home.hide-values.v1'), isTrue);
  });
}
