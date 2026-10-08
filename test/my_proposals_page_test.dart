import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/my_proposals_page.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/widgets/sent_proposal_card.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Penawaranku: every "Penuhi Bid" the user sent, across all cards. Each row
/// names its card, since unlike a card's own page nothing else on screen
/// does.
SentProposalModel _sent(
  String slug,
  String cardName,
  BidProposalStatus status,
) => SentProposalModel(
  slug: slug,
  card: CardModel(
    id: slug.hashCode,
    category: CardCategory.pokemon,
    nameId: cardName,
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '025/165',
    rarity: 'C',
  ),
  condition: CardCondition.nm,
  proposedQuantity: 1,
  status: status,
  bidPrice: 50000,
  buyerUsername: 'pembeli',
);

Future<void> _pump(WidgetTester tester, List<SentProposalModel> sent) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sentProposalsProvider.overrideWith((ref) async => sent)],
      child: MaterialApp(theme: AppTheme.light, home: const MyProposalsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final sent = [
    _sent('a', 'Pikachu', BidProposalStatus.pending),
    _sent('b', 'Charizard', BidProposalStatus.accepted),
    _sent('c', 'Bulbasaur', BidProposalStatus.rejected),
  ];

  testWidgets('lists every sent proposal under its card', (tester) async {
    await _pump(tester, sent);

    expect(find.text('Penawaranku'), findsOneWidget);
    expect(find.byType(SentProposalCard), findsNWidgets(3));
    for (final name in ['Pikachu', 'Charizard', 'Bulbasaur']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('the status chips count and narrow the list', (tester) async {
    await _pump(tester, sent);

    expect(find.text('Semua (3)'), findsOneWidget);
    expect(find.text('Menunggu (1)'), findsOneWidget);

    // The chips scroll sideways; bring this one into view as a thumb would.
    await tester.ensureVisible(find.text('Diterima (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diterima (1)'));
    await tester.pumpAndSettle();
    expect(find.byType(SentProposalCard), findsOneWidget);
    expect(find.text('Charizard'), findsOneWidget);
  });

  testWidgets('only a settled proposal can be cleared away', (tester) async {
    await _pump(tester, sent);
    // Two settled rows, one pending: `dismiss_bid_proposal` refuses that one.
    expect(find.byTooltip('Hapus dari daftar'), findsNWidgets(2));
  });

  testWidgets('says how to get started when nothing has been sent', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('Belum ada penawaran'), findsOneWidget);
    expect(find.byType(SentProposalCard), findsNothing);
  });

  test('every chip but Semua matches one status', () {
    for (final filter in MyProposalsFilter.values) {
      if (filter == MyProposalsFilter.all) continue;
      expect(filter.status, isNotNull);
    }
  });
}
