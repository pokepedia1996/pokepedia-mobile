import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/evolution_chain.dart';

/// `get_evolution_pool` ends in `SELECT DISTINCT ON (name_id) ... ORDER BY
/// name_id, id`, so each species comes back as exactly one row — whichever
/// print has the lowest id. That print is often an old one with no
/// `evolves_from`, and it isn't necessarily the card being viewed, which is
/// why the chain has to count the current card's own edge. Reproduces the
/// live Beedrill case: the pool's Beedrill row is id 339 with a null
/// `evolves_from` while the card on screen (an Indonesian print) knows it
/// evolves from Kakuna.
CardModel _card(
  int id,
  String name, {
  String? evolvesFrom,
  CardCategory category = CardCategory.pokemon,
}) {
  return CardModel(
    id: id,
    category: category,
    nameId: name,
    expansionCode: 'SVI',
    packSlug: 'svi',
    collectorNumber: '$id',
    rarity: 'Common',
    details: CardDetails(evolvesFrom: evolvesFrom),
  );
}

void main() {
  group('buildEvolutionStages', () {
    test('uses the viewed card\'s own evolves_from, not the pool\'s row', () {
      final current = _card(20422, 'Beedrill', evolvesFrom: 'Kakuna');
      final pool = [
        _card(339, 'Beedrill'), // lowest id, no evolves_from
        _card(985, 'Kakuna', evolvesFrom: 'Weedle'),
        _card(1038, 'Weedle'),
        _card(3758, 'Beedrill ex', evolvesFrom: 'Kakuna'),
      ];

      final stages = buildEvolutionStages(current, pool);

      expect(stages, isNotNull, reason: 'the whole line must be visible');
      expect(stages!.map((s) => s.cards.map((c) => c.name).toList()), [
        ['Weedle'],
        ['Kakuna'],
        ['Beedrill', 'Beedrill ex'],
      ]);
    });

    test('shows the viewed print in its own stage', () {
      final current = _card(20422, 'Beedrill', evolvesFrom: 'Kakuna');
      final stages = buildEvolutionStages(current, [
        _card(339, 'Beedrill'),
        _card(985, 'Kakuna', evolvesFrom: 'Weedle'),
        _card(1038, 'Weedle'),
      ]);

      final beedrill = stages!.last.cards.single;
      expect(beedrill.cardId, 20422);
    });

    test('a chain missing its middle still resolves from the card', () {
      // Kakuna collapsed to a print with no parent: the walk stops there,
      // but Kakuna -> Beedrill is still two stages.
      final stages = buildEvolutionStages(
        _card(20422, 'Beedrill', evolvesFrom: 'Kakuna'),
        [_card(985, 'Kakuna')],
      );

      expect(stages, isNotNull);
      expect(stages!.length, 2);
      expect(stages.first.cards.single.name, 'Kakuna');
    });

    test('returns null for a single-stage Pokemon', () {
      final stages = buildEvolutionStages(_card(500, 'Ditto'), [
        _card(500, 'Ditto'),
      ]);

      expect(stages, isNull);
    });

    test('ignores non-Pokemon rows', () {
      final stages = buildEvolutionStages(
        _card(20422, 'Beedrill', evolvesFrom: 'Kakuna'),
        [
          _card(985, 'Kakuna', evolvesFrom: 'Weedle'),
          _card(1038, 'Weedle'),
          _card(700, 'Potion', category: CardCategory.trainer),
        ],
      );

      final names = stages!.expand((s) => s.cards.map((c) => c.name));
      expect(names, isNot(contains('Potion')));
    });
  });
}
