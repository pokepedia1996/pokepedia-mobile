import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/pack_detail_page.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';

/// The two bulk actions were a full-width pair of buttons under the meta
/// line — two sentences of shouting for something done once, if ever. They
/// belong behind the title's menu.
const _pack = PackModel(
  slug: 'sv2a',
  name: 'Ancaman Bayangan',
  mark: 'SV2a',
  series: 'Scarlet & Violet',
  releaseDate: '2026-01-01',
  cardCount: 2,
);

const _cards = [
  CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Charizard ex',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '001/165',
    rarity: 'SAR',
  ),
  CardModel(
    id: 2,
    category: CardCategory.pokemon,
    nameId: 'Pikachu',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '002/165',
    rarity: 'Rare',
  ),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Future<void> _pump(WidgetTester tester) async {
  // Wide: the harness's square fallback font overflows the card grid at
  // phone widths, for reasons unrelated to the header.
  tester.view.physicalSize = const Size(2200, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        packDetailProvider('sv2a').overrideWith((ref) async => _pack),
        packCardsProvider('sv2a').overrideWith((ref) async => _cards),
        packCardPricesProvider('sv2a').overrideWith((ref) async => {}),
        packOwnedQuantitiesProvider('sv2a').overrideWith((ref) async => {}),
        listsProvider.overrideWith((ref) async => []),
        seriesGroupsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PackDetailPage(packSlug: 'sv2a'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bulk actions are behind the title menu', (tester) async {
    await _pump(tester);

    // Not shouting from the header any more.
    expect(find.text('Tambah Semua ke Koleksi'), findsNothing);
    expect(find.text('Hapus Semua dari Koleksi'), findsNothing);
    expect(find.text('Tambah semua'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();

    expect(find.text('Tambah semua'), findsOneWidget);
    expect(find.text('Hapus semua'), findsOneWidget);
  });

  testWidgets('the expansion name still leads the header', (tester) async {
    await _pump(tester);

    expect(find.text('Ancaman Bayangan'), findsOneWidget);
    expect(find.textContaining('Dirilis:'), findsOneWidget);
  });
}
