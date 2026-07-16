import 'pokemon_type.dart';

/// `cards.category` check constraint.
enum CardCategory { pokemon, trainer, energy }

extension CardCategoryX on CardCategory {
  String get raw {
    switch (this) {
      case CardCategory.pokemon:
        return 'Pokemon';
      case CardCategory.trainer:
        return 'Trainer';
      case CardCategory.energy:
        return 'Energy';
    }
  }

  String get labelId {
    switch (this) {
      case CardCategory.pokemon:
        return 'Pokémon';
      case CardCategory.trainer:
        return 'Trainer';
      case CardCategory.energy:
        return 'Energy';
    }
  }
}

enum TrainerSubtype { item, supporter, stadium, tool }

extension TrainerSubtypeX on TrainerSubtype {
  String get labelId {
    switch (this) {
      case TrainerSubtype.item:
        return 'Item';
      case TrainerSubtype.supporter:
        return 'Supporter';
      case TrainerSubtype.stadium:
        return 'Stadium';
      case TrainerSubtype.tool:
        return 'Pokémon Tool';
    }
  }
}

enum EvolutionStage { basic, stage1, stage2 }

extension EvolutionStageX on EvolutionStage {
  String get labelId {
    switch (this) {
      case EvolutionStage.basic:
        return 'Basic';
      case EvolutionStage.stage1:
        return 'Stage 1';
      case EvolutionStage.stage2:
        return 'Stage 2';
    }
  }
}

/// `cards.language` check constraint.
enum CardLanguage { id, en, jp }

extension CardLanguageX on CardLanguage {
  String get raw => name;

  String get labelId {
    switch (this) {
      case CardLanguage.id:
        return 'Indonesia';
      case CardLanguage.en:
        return 'English';
      case CardLanguage.jp:
        return 'Japan';
    }
  }
}

/// One entry of a card's weakness/resistance (`details.weakness` /
/// `details.resistance` jsonb).
class TypeModifier {
  const TypeModifier({required this.type, required this.value});

  final PokemonType type;
  final String value;
}

/// One entry of `details.attacks[]`.
class AttackModel {
  const AttackModel({
    required this.name,
    required this.cost,
    required this.damage,
    this.effect,
  });

  final String name;
  final List<PokemonType> cost;
  final String damage;
  final String? effect;
}

/// Category-specific fields folded out of the `cards.details` jsonb column.
class CardDetails {
  const CardDetails({
    this.hp,
    this.pokemonTypes = const [],
    this.evolutionStage,
    this.evolvesFrom,
    this.attacks = const [],
    this.weakness,
    this.resistance,
    this.retreatCost,
    this.trainerSubtype,
    this.energyType,
  });

  final int? hp;
  final List<PokemonType> pokemonTypes;
  final EvolutionStage? evolutionStage;
  final String? evolvesFrom;
  final List<AttackModel> attacks;
  final TypeModifier? weakness;
  final TypeModifier? resistance;
  final int? retreatCost;
  final TrainerSubtype? trainerSubtype;
  final PokemonType? energyType;
}

/// A single Pokemon TCG card, mirroring `public.cards` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class CardModel {
  const CardModel({
    required this.id,
    required this.category,
    required this.nameId,
    required this.expansionCode,
    required this.packSlug,
    required this.collectorNumber,
    required this.rarity,
    this.regulationMark,
    this.illustrator,
    this.language = CardLanguage.id,
    this.variant = 'normal',
    this.details = const CardDetails(),
    this.marketPrice,
    this.owned = 0,
  });

  final int id;
  final CardCategory category;
  final String nameId;
  final String expansionCode;
  final String packSlug;
  final String collectorNumber;
  final String? rarity;
  final String? regulationMark;
  final String? illustrator;
  final CardLanguage language;
  final String variant;
  final CardDetails details;
  final int? marketPrice;
  final int owned;

  /// Convenience alias — most UI code just wants the display name.
  String get name => nameId;

  CardModel copyWith({int? owned}) => CardModel(
    id: id,
    category: category,
    nameId: nameId,
    expansionCode: expansionCode,
    packSlug: packSlug,
    collectorNumber: collectorNumber,
    rarity: rarity,
    regulationMark: regulationMark,
    illustrator: illustrator,
    language: language,
    variant: variant,
    details: details,
    marketPrice: marketPrice,
    owned: owned ?? this.owned,
  );
}
