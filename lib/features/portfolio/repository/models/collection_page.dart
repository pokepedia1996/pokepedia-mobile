import '../../../../shared/models/card_market_price.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/pokemon_type.dart';
import '../../../../shared/utils/card_filtering.dart';

/// One row of `get_collection_cards` — a `collection_cards` row with its card
/// and cached price, plus the sort key the next page continues from.
///
/// Ports `toCollectionPageRow` from
/// `pokepedia-web/features/collection/api/collection-card-row.ts`.
class CollectionCardRow {
  const CollectionCardRow({
    required this.card,
    required this.collectionCardId,
    this.cursorNum,
    this.cursorText,
    this.cursorTs,
  });

  final CardModel card;

  /// `collection_cards.id`. One card can sit in a collection under several
  /// variant keys, so this, not the card id, is what identifies a row.
  final String collectionCardId;

  /// The price-asc sentinel for an unpriced card is the bigint maximum, so
  /// this has to stay a 64-bit int end to end — never a double.
  final int? cursorNum;
  final String? cursorText;
  final DateTime? cursorTs;

  factory CollectionCardRow.fromRpc(Map<String, dynamic> row) {
    final cardId = (row['card_id'] as num).toInt();
    final card = CardModel.fromRow({
      'id': cardId,
      'name_id': row['name'],
      'expansion_code': row['expansion_code'],
      'collector_number': row['collector_number'],
      'rarity': row['rarity'],
      'category': row['category'],
      'image_url': row['image_url'],
      'language': row['language'],
      'variant': row['variant'],
      'details': {'card_type': row['card_type']},
    });
    final price = row['price'] as num?;

    return CollectionCardRow(
      card: card.copyWith(
        owned: (row['quantity'] as num?)?.toInt() ?? 0,
        price: price == null
            ? null
            : CardMarketPrice.fromRow({
                'card_id': cardId,
                'price': price,
                'condition': row['price_condition'],
                'source': row['price_source'],
                'price_7d_ago': row['price_7d_ago'],
              }),
      ),
      collectionCardId: row['collection_card_id'] as String,
      cursorNum: (row['cursor_num'] as num?)?.toInt(),
      cursorText: row['cursor_text'] as String?,
      cursorTs: row['cursor_ts'] == null
          ? null
          : DateTime.parse(row['cursor_ts'] as String),
    );
  }
}

class CollectionCardsPage {
  const CollectionCardsPage({required this.rows, this.total});

  final List<CollectionCardRow> rows;

  /// Matches for the current search and filters. The RPC only counts on the
  /// first page and returns null on every later one.
  final int? total;
}

/// `get_collection_summary` — the whole collection's totals, independent of
/// any search or filter.
class CollectionSummary {
  const CollectionSummary({
    required this.totalValue,
    required this.uniqueCount,
    required this.totalCount,
    required this.valueNow,
    required this.value7dAgo,
  });

  static const empty = CollectionSummary(
    totalValue: 0,
    uniqueCount: 0,
    totalCount: 0,
    valueNow: 0,
    value7dAgo: 0,
  );

  final int totalValue;

  /// Rows, so a card held under two variants counts twice — what the grid
  /// lists.
  final int uniqueCount;

  /// Copies.
  final int totalCount;

  /// Today's and last week's value over only the cards priced both times.
  final int valueNow;
  final int value7dAgo;

  bool get isEmpty => uniqueCount == 0;

  factory CollectionSummary.fromJson(Map<String, dynamic> json) {
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CollectionSummary(
      totalValue: read('total_value'),
      uniqueCount: read('unique_count'),
      totalCount: read('total_count'),
      valueNow: read('value_now'),
      value7dAgo: read('value_7d_ago'),
    );
  }
}

/// `get_collection_facets` — the distinct values the collection holds, as
/// the database spells them.
///
/// The raw spellings are kept because the catalog is not consistent: the
/// trainer tool subtype is stored as `Tool`, `Pokémon Tool` and
/// `Pokemon Tool`. A filter has to send every spelling the chip stands for,
/// or most of the cards it names never match.
class CollectionFacets {
  const CollectionFacets({
    this.categories = const [],
    this.types = const [],
    this.rarities = const [],
    this.evolutionStages = const [],
    this.trainerSubtypes = const [],
    this.regulationMarks = const [],
  });

  final List<String> categories;
  final List<String> types;

  /// Already in rarity order.
  final List<String> rarities;
  final List<String> evolutionStages;
  final List<String> trainerSubtypes;
  final List<String> regulationMarks;

  factory CollectionFacets.fromJson(Map<String, dynamic> json) {
    List<String> read(String key) =>
        (json[key] as List<dynamic>? ?? const []).whereType<String>().toList();
    return CollectionFacets(
      categories: read('categories'),
      types: read('types'),
      rarities: read('rarities'),
      evolutionStages: read('evolutionStages'),
      trainerSubtypes: read('trainerSubtypes'),
      regulationMarks: read('regulationMarks'),
    );
  }

  CardFilterOptions toFilterOptions() => CardFilterOptions(
    categories: _parsed(categories, _categoryFromRaw),
    types: _parsed(types, pokemonTypeFromRaw),
    rarities: rarities,
    evolutionStages: _parsed(evolutionStages, EvolutionStageX.fromRaw),
    trainerSubtypes: _parsed(trainerSubtypes, TrainerSubtypeX.fromRaw),
    regulationMarks: regulationMarks,
  );

  List<String> evolutionStagesFor(Set<EvolutionStage> selected) => _rawFor(
    selected,
    evolutionStages,
    EvolutionStageX.fromRaw,
    (stage) => stage.labelId,
  );

  List<String> trainerSubtypesFor(Set<TrainerSubtype> selected) => _rawFor(
    selected,
    trainerSubtypes,
    TrainerSubtypeX.fromRaw,
    (subtype) => subtype.labelId,
  );

  /// Unlike [CardCategoryX.fromRaw], which reads anything unknown as a
  /// Pokemon card — fine for a row, wrong for a chip.
  static CardCategory? _categoryFromRaw(String raw) {
    for (final category in CardCategory.values) {
      if (category.raw == raw) return category;
    }
    return null;
  }

  static List<T> _parsed<T>(List<String> raws, T? Function(String) parse) {
    final seen = <T>{};
    for (final raw in raws) {
      final value = parse(raw);
      if (value != null) seen.add(value);
    }
    return seen.toList();
  }

  /// Every stored spelling of the selected values. Falls back to the
  /// canonical label for a value the facets don't list, so a filter carried
  /// over from another collection still narrows rather than vanishing.
  static List<String> _rawFor<T>(
    Set<T> selected,
    List<String> raws,
    T? Function(String) parse,
    String Function(T) label,
  ) {
    final out = <String>{};
    for (final value in selected) {
      final spellings = raws.where((raw) => parse(raw) == value);
      if (spellings.isEmpty) {
        out.add(label(value));
      } else {
        out.addAll(spellings);
      }
    }
    return out.toList();
  }
}
