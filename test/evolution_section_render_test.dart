import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/card_details_section.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The evolution section renders inside the card detail page's `ListView`,
/// so its children are laid out with an unbounded height. Pins that it
/// actually paints there instead of throwing.
CardModel _card(int id, String name, {String? evolvesFrom}) {
  return CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: name,
    expansionCode: 'SVI',
    packSlug: 'svi',
    collectorNumber: '$id',
    rarity: 'Common',
    details: CardDetails(evolvesFrom: evolvesFrom),
  );
}

void main() {
  testWidgets('renders inside a ListView', (tester) async {
    final current = _card(20422, 'Beedrill', evolvesFrom: 'Kakuna');
    final pool = [
      _card(339, 'Beedrill'),
      _card(985, 'Kakuna', evolvesFrom: 'Weedle'),
      _card(1038, 'Weedle'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          evolutionPoolProvider((
            name: current.name,
            evolvesFrom: current.details.evolvesFrom,
          )).overrideWith((ref) async => pool),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              children: [
                EvolutionSection(
                  card: current,
                  selectedOverride: const {},
                  onCycle: (_, __, ___, ____) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Evolusi'), findsOneWidget);
    expect(find.text('Weedle'), findsOneWidget);
  });
}
