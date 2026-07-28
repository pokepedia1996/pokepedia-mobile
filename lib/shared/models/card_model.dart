import '../../core/utils/image_url.dart';
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

  static CardCategory fromRaw(String? raw) {
    switch (raw) {
      case 'Trainer':
        return CardCategory.trainer;
      case 'Energy':
        return CardCategory.energy;
      case 'Pokemon':
      default:
        return CardCategory.pokemon;
    }
  }

  String get labelId {
    switch (this) {
      case CardCategory.pokemon:
        return 'Pokemon';
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
        return 'Pokemon Tool';
    }
  }

  static TrainerSubtype? fromRaw(String? raw) {
    if (raw == null) return null;
    final needle = raw.trim().toLowerCase();
    for (final subtype in TrainerSubtype.values) {
      if (subtype.labelId.toLowerCase() == needle || subtype.name == needle) {
        return subtype;
      }
    }
    return null;
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

  static EvolutionStage? fromRaw(String? raw) {
    if (raw == null) return null;
    final needle = raw.trim().toLowerCase();
    for (final stage in EvolutionStage.values) {
      if (stage.labelId.toLowerCase() == needle || stage.name == needle) {
        return stage;
      }
    }
    return null;
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

  static CardLanguage fromRaw(String? raw) {
    switch (raw) {
      case 'en':
        return CardLanguage.en;
      case 'jp':
        return CardLanguage.jp;
      case 'id':
      default:
        return CardLanguage.id;
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
    this.pokedexNumber,
    this.pokedexHeight,
    this.pokedexWeight,
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

  /// `details.pokedex.{number,height,weight}` — species stats shown in the
  /// card detail page's "Pokédex" section.
  final int? pokedexNumber;
  final String? pokedexHeight;
  final String? pokedexWeight;

  /// Decodes the `cards.details` jsonb column. Unrecognized/missing keys
  /// fall back to their defaults rather than throwing — a malformed field
  /// shouldn't blow up the whole card row.
  factory CardDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CardDetails();
    final cardType = json['card_type'] as String?;
    final weaknessJson = json['weakness'] as Map<String, dynamic>?;
    final resistanceJson = json['resistance'] as Map<String, dynamic>?;
    final attacksJson = json['attacks'] as List<dynamic>?;
    final pokedexJson = json['pokedex'] as Map<String, dynamic>?;

    return CardDetails(
      hp: json['hp'] as int?,
      pokemonTypes: pokemonTypesFromRaw(cardType),
      evolutionStage: EvolutionStageX.fromRaw(json['evolution_stage'] as String?),
      evolvesFrom: json['evolves_from'] as String?,
      attacks: attacksJson == null
          ? const []
          : attacksJson
                .whereType<Map<String, dynamic>>()
                .map(
                  (a) => AttackModel(
                    name: a['name'] as String? ?? '',
                    cost: pokemonTypesFromRaw(
                      (a['energy_cost'] as List<dynamic>?)?.whereType<String>().join('/'),
                    ),
                    damage: a['damage'] as String? ?? '',
                    effect: a['description'] as String?,
                  ),
                )
                .toList(),
      weakness: weaknessJson == null
          ? null
          : pokemonTypeFromRaw(weaknessJson['type'] as String?) == null
          ? null
          : TypeModifier(
              type: pokemonTypeFromRaw(weaknessJson['type'] as String?)!,
              value: weaknessJson['modifier'] as String? ?? '',
            ),
      resistance: resistanceJson == null
          ? null
          : pokemonTypeFromRaw(resistanceJson['type'] as String?) == null
          ? null
          : TypeModifier(
              type: pokemonTypeFromRaw(resistanceJson['type'] as String?)!,
              value: resistanceJson['modifier'] as String? ?? '',
            ),
      retreatCost: json['retreat_cost'] as int?,
      trainerSubtype: TrainerSubtypeX.fromRaw(json['trainer_subtype'] as String?),
      energyType: pokemonTypeFromRaw(cardType),
      pokedexNumber: pokedexJson?['number'] as int?,
      pokedexHeight: pokedexJson?['height'] as String?,
      pokedexWeight: pokedexJson?['weight'] as String?,
    );
  }
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
    this.imageUrl,
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

  /// CDN-resolved `cards.image_url` (see `proxyImageUrl`). Null for dummy
  /// (non-catalog) data, in which case UI falls back to a placeholder.
  final String? imageUrl;

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
    imageUrl: imageUrl,
  );

  /// Maps a `cards` row (optionally with an embedded `expansions` join) as
  /// returned by Supabase, mirroring `mapCardRow` in
  /// `pokepedia-web/lib/data/client.ts`.
  factory CardModel.fromRow(Map<String, dynamic> row) {
    final expansionCode = row['expansion_code'] as String? ?? '';
    final rarityRaw = row['rarity'] as String?;
    return CardModel(
      id: row['id'] as int,
      category: CardCategoryX.fromRaw(row['category'] as String?),
      nameId: row['name_id'] as String? ?? '',
      expansionCode: expansionCode,
      packSlug: expansionCode.toLowerCase(),
      collectorNumber: row['collector_number'] as String? ?? '',
      rarity: (rarityRaw == null || rarityRaw.isEmpty) ? 'Tanpa tanda' : rarityRaw,
      regulationMark: row['regulation_mark'] as String?,
      illustrator: row['illustrator'] as String?,
      language: CardLanguageX.fromRaw(row['language'] as String?),
      variant: row['variant'] as String? ?? 'normal',
      details: CardDetails.fromJson(row['details'] as Map<String, dynamic>?),
      imageUrl: proxyImageUrl(row['image_url'] as String?),
    );
  }
}
