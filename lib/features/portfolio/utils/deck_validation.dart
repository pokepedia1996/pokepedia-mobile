import '../../../shared/models/card_model.dart';
import '../repository/models/deck_card_entry.dart';

/// Ports `lib/products/deck-validation.ts`.
const deckMaxCards = 60;
const deckMaxCopies = 4;
const _basicEnergyPrefix = 'Energi Dasar';

bool isBasicEnergy(CardModel card) =>
    card.category == CardCategory.energy &&
    card.name.startsWith(_basicEnergyPrefix);

String stripCardNameBrackets(String name) =>
    name.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();

sealed class DeckValidationError {
  const DeckValidationError();
}

class DeckErrorNot60Cards extends DeckValidationError {
  const DeckErrorNot60Cards(this.total);
  final int total;
}

class DeckErrorNoBasicPokemon extends DeckValidationError {
  const DeckErrorNoBasicPokemon();
}

class DeckErrorOver4Copies extends DeckValidationError {
  const DeckErrorOver4Copies(this.cardName, this.count);
  final String cardName;
  final int count;
}

class DeckErrorOverAce extends DeckValidationError {
  const DeckErrorOverAce(this.count);
  final int count;
}

class DeckValidationResult {
  const DeckValidationResult({
    required this.totalCards,
    required this.errors,
    required this.pokemonCount,
    required this.trainerCount,
    required this.energyCount,
  });

  final int totalCards;
  final List<DeckValidationError> errors;
  final int pokemonCount;
  final int trainerCount;
  final int energyCount;

  bool get isValid => errors.isEmpty;
  bool get hasOverCopies => errors.any((e) => e is DeckErrorOver4Copies);
}

DeckValidationResult validateDeck(List<DeckCardEntry> entries) {
  var totalCards = 0;
  var pokemonCount = 0;
  var trainerCount = 0;
  var energyCount = 0;
  var aceCount = 0;
  var hasBasicPokemon = false;
  final nameQuantities = <String, int>{};
  final errors = <DeckValidationError>[];

  for (final e in entries) {
    totalCards += e.quantity;
    switch (e.card.category) {
      case CardCategory.pokemon:
        pokemonCount += e.quantity;
        if (e.card.details.evolutionStage == EvolutionStage.basic) {
          hasBasicPokemon = true;
        }
      case CardCategory.trainer:
        trainerCount += e.quantity;
      case CardCategory.energy:
        energyCount += e.quantity;
    }
    if (!isBasicEnergy(e.card)) {
      final baseName = stripCardNameBrackets(e.card.name);
      nameQuantities[baseName] = (nameQuantities[baseName] ?? 0) + e.quantity;
    }
    if (e.card.rarity == 'ACE') aceCount += e.quantity;
  }

  if (totalCards != deckMaxCards) errors.add(DeckErrorNot60Cards(totalCards));
  if (!hasBasicPokemon) errors.add(const DeckErrorNoBasicPokemon());
  for (final entry in nameQuantities.entries) {
    if (entry.value > deckMaxCopies) {
      errors.add(DeckErrorOver4Copies(entry.key, entry.value));
    }
  }
  if (aceCount > 1) errors.add(DeckErrorOverAce(aceCount));

  return DeckValidationResult(
    totalCards: totalCards,
    errors: errors,
    pokemonCount: pokemonCount,
    trainerCount: trainerCount,
    energyCount: energyCount,
  );
}

String deckValidationErrorMessage(DeckValidationError error) => switch (error) {
  DeckErrorNot60Cards(:final total) =>
    total < deckMaxCards
        ? 'Butuh ${deckMaxCards - total} kartu lagi'
        : 'Kartu lebih dari $deckMaxCards tidak valid ($total)',
  DeckErrorNoBasicPokemon() => 'Butuh minimal 1 Pokemon Basic',
  DeckErrorOver4Copies(:final cardName, :final count) =>
    '"$cardName" melebihi batas 4 salinan ($count)',
  DeckErrorOverAce(:final count) => 'Hanya boleh 1 kartu ACE per dek ($count)',
};

/// Maps `/^Cannot have more than 4 copies/` etc. RPC errors from
/// `upsert_deck_card` to Indonesian copy, mirroring how the page shows a
/// toast on failure.
String translateDeckCardError(String raw) {
  if (raw.contains('Cannot have more than 4 copies')) {
    return 'Maksimal $deckMaxCopies salinan kartu ini';
  }
  if (raw.contains('Only 1 ACE card allowed')) {
    return 'Hanya boleh 1 kartu ACE per dek';
  }
  return 'Gagal memperbarui kartu di deck';
}
