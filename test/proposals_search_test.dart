import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/proposals_page.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposal_card_group.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The Proposal page's search: which cards a query keeps.
ProposalCardGroup _group(String name, String set, String number) =>
    ProposalCardGroup(
      card: CardModel(
        id: 1,
        category: CardCategory.pokemon,
        nameId: name,
        expansionCode: set,
        packSlug: set.toLowerCase(),
        collectorNumber: number,
        rarity: 'Rare',
      ),
    );

void main() {
  final pikachu = _group('Pikachu ex', 'SV8', '094/191');

  test('nothing typed keeps every card', () {
    expect(matchesProposalSearch(pikachu, ''), isTrue);
    expect(matchesProposalSearch(pikachu, '   '), isTrue);
  });

  test('by name, ignoring case', () {
    expect(matchesProposalSearch(pikachu, 'PIKA'), isTrue);
    expect(matchesProposalSearch(pikachu, 'raichu'), isFalse);
  });

  test('by set code or number, with or without #', () {
    expect(matchesProposalSearch(pikachu, 'sv8'), isTrue);
    expect(matchesProposalSearch(pikachu, '094'), isTrue);
    expect(matchesProposalSearch(pikachu, '#94'), isTrue);
  });

  test('every word has to match, in any order', () {
    expect(matchesProposalSearch(pikachu, 'sv8 pikachu'), isTrue);
    expect(matchesProposalSearch(pikachu, 'pikachu sv7'), isFalse);
  });
}
