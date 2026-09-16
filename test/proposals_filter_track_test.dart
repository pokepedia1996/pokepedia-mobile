import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/proposals_page.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposal_card_group.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposals_summary.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The feed's filter is one control with one answer — web draws it as a
/// track with the active option raised, not as a row of separate pills that
/// each look switchable on their own.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

ProposalCardGroup _group({required int id, int needsAction = 0}) {
  final group = ProposalCardGroup(
    card: CardModel(
      id: id,
      category: CardCategory.pokemon,
      nameId: 'Alakazam $id',
      expansionCode: 'EX',
      packSlug: 'ex',
      collectorNumber: '00$id/165',
      rarity: 'Rare',
    ),
  );
  // "Perlu aksi" is proposals received, which are the ones awaiting you.
  group.receivedPending = needsAction;
  group.receivedTotal = needsAction;
  return group;
}

Future<void> _pump(WidgetTester tester, List<ProposalCardGroup> groups) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        proposalCardFeedProvider.overrideWith((ref) async => groups),
        proposalsSummaryProvider.overrideWith(
          (ref) async => const ProposalsSummary(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProposalsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the options sit in one track, the active one raised', (
    tester,
  ) async {
    await _pump(tester, [_group(id: 1), _group(id: 2, needsAction: 1)]);

    expect(find.text('2 kartu dengan aktivitas'), findsOneWidget);
    expect(find.text('Semua (2)'), findsOneWidget);
    expect(find.text('Perlu aksi (1)'), findsOneWidget);

    // The selected one is the only one carrying a background of its own.
    final boxes = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .toList();
    final filled = boxes.where((c) => c != null && c != Colors.transparent);
    expect(filled.length, 1);
  });

  testWidgets('the track spans the width, the options start at the left', (
    tester,
  ) async {
    await _pump(tester, [_group(id: 1), _group(id: 2, needsAction: 1)]);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final scroller = find.ancestor(
      of: find.text('Semua (2)'),
      matching: find.byType(SingleChildScrollView),
    );
    // Edge to edge inside the page's 16pt gutters and the track's own 4pt
    // padding, rather than shrink-wrapping the options.
    expect(tester.getSize(scroller).width, closeTo(width - 32 - 8, 1));

    // And the first option sits against the left of it, not centred.
    final trackLeft = tester.getTopLeft(scroller).dx;
    final firstChip = tester.getTopLeft(find.text('Semua (2)')).dx;
    expect(firstChip - trackLeft, lessThan(24));
  });

  testWidgets('an option with nothing behind it is dropped', (tester) async {
    await _pump(tester, [_group(id: 1)]);

    expect(find.text('Semua (1)'), findsOneWidget);
    expect(find.textContaining('Perlu aksi'), findsNothing);
  });
}
