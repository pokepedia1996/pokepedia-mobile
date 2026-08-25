import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/related_cards_section.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The rail lives at the bottom of the card detail page's `ListView`, so it
/// is laid out with an unbounded height — the same condition that had the
/// info panel above it throwing. These pin that it survives there.
CardModel _print(int id, String expansionCode, String collectorNumber) {
  return CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: 'Beedrill',
    expansionCode: expansionCode,
    packSlug: expansionCode.toLowerCase(),
    collectorNumber: collectorNumber,
    rarity: 'U',
  );
}

/// The Indonesian Beedrill prints as they exist in production.
final _related = [
  _print(31104, 'SV2a', '015/165'),
  _print(28428, 'SC3b', '006/158'),
  _print(27054, 'S8b', '003/184'),
];

final _current = _print(20422, 'AC3a', '006/205');

Widget _host(List<CardModel> related) {
  return ProviderScope(
    overrides: [
      relatedCardsProvider((
        name: _current.name,
        excludeId: _current.id,
      )).overrideWith((ref) async => related),
      // No symbols loaded: the thumbs fall back to the expansion code, which
      // is web's own fallback when a set symbol is missing.
      seriesGroupsProvider.overrideWith((ref) async => []),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [RelatedCardsSection(card: _current)],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the rail inside a ListView', (tester) async {
    await tester.pumpWidget(_host(_related));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kartu Terkait'), findsOneWidget);
    expect(find.text('SV2A'), findsOneWidget);
    expect(find.text('Beedrill'), findsNWidgets(_related.length));
  });

  testWidgets('renders nothing when the card has no other prints', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kartu Terkait'), findsNothing);
  });
}
