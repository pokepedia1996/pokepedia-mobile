import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/collection_page.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/pokemon_type.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';

/// The `get_collection_cards` contract web's Koleksi already relies on — see
/// `supabase/schemas/functions/get_collection_cards.sql` in pokepedia-web.
Map<String, dynamic> _rpcRow({
  String id = 'cc-1',
  Object? price = 25000,
  Object? cursorNum = 25000,
}) => {
  'collection_card_id': id,
  'card_id': 42,
  'quantity': 3,
  'variant_key': 'normal',
  'notes': null,
  'updated_at': '2026-10-01T00:00:00+00:00',
  'name': 'Pikachu',
  'image_url': null,
  'collector_number': '025/165',
  'rarity': null,
  'category': 'Pokemon',
  'card_type': 'Lightning',
  'language': 'id',
  'variant': 'normal',
  'expansion_code': 'SV2a',
  'expansion_name': 'Pokemon Card 151',
  'set_symbol_url': null,
  'price': price,
  'price_7d_ago': 20000,
  'price_condition': 'NM',
  'price_source': 'confirmed',
  'cursor_num': cursorNum,
  'cursor_text': null,
  'cursor_ts': null,
  'total_count': 1,
};

void main() {
  group('CollectionCardRow.fromRpc', () {
    test('reads the card, its quantity and its price', () {
      final row = CollectionCardRow.fromRpc(_rpcRow());

      expect(row.collectionCardId, 'cc-1');
      expect(row.card.id, 42);
      expect(row.card.name, 'Pikachu');
      expect(row.card.packSlug, 'sv2a');
      expect(row.card.owned, 3);
      expect(row.card.rarity, 'Tanpa tanda');
      expect(row.card.details.pokemonTypes, [PokemonType.lightning]);
      expect(row.card.marketPrice, 25000);
      expect(row.card.price7dAgo, 20000);
      expect(row.card.priceSource, CardPriceSource.confirmed);
    });

    test('an unpriced card stays unpriced', () {
      final row = CollectionCardRow.fromRpc(_rpcRow(price: null));
      expect(row.card.marketPrice, isNull);
    });

    test('keeps the bigint price-asc sentinel exact', () {
      // An unpriced card sorts last under price-asc on the bigint maximum. A
      // double would round it past the range and the next page would fail.
      const sentinel = 9223372036854775807;
      final row = CollectionCardRow.fromRpc(
        _rpcRow(price: null, cursorNum: sentinel),
      );
      expect(row.cursorNum, sentinel);
    });
  });

  group('collectionPageParams', () {
    final after = CollectionCardRow.fromRpc(_rpcRow(id: 'cc-last'));

    test('sends unused facets as null, never as an empty array', () {
      final params = collectionPageParams(
        collectionId: null,
        sort: CardSortOption.priceDesc,
        filters: const CardFilters(search: '  '),
      );

      for (final key in [
        'p_categories',
        'p_types',
        'p_rarities',
        'p_evolution_stages',
        'p_trainer_subtypes',
        'p_regulation_marks',
        'p_search',
        'p_cursor_id',
      ]) {
        expect(params[key], isNull, reason: key);
      }
      expect(params['p_sort'], 'price-desc');
      expect(params['p_offset'], 0);
      expect(params['p_limit'], collectionPageSize);
    });

    test('continues the keyset sorts from the last row', () {
      final params = collectionPageParams(
        collectionId: 'list-1',
        sort: CardSortOption.priceAsc,
        filters: const CardFilters(),
        after: after,
        offset: 48,
      );

      expect(params['p_collection_id'], 'list-1');
      expect(params['p_cursor_id'], 'cc-last');
      expect(params['p_cursor_num'], 25000);
      expect(params['p_offset'], 0);
    });

    test('pages the number and set sorts by offset instead', () {
      // They have no cursor key; a cursor sent with one is ignored by the
      // RPC and the first page comes back again.
      for (final sort in [CardSortOption.numberAsc, CardSortOption.setDesc]) {
        final params = collectionPageParams(
          collectionId: null,
          sort: sort,
          filters: const CardFilters(),
          after: after,
          offset: 96,
        );
        expect(params['p_cursor_id'], isNull, reason: sort.raw);
        expect(params['p_offset'], 96, reason: sort.raw);
      }
    });

    test('sends every stored spelling of a chosen subtype', () {
      const facets = CollectionFacets(
        trainerSubtypes: ['Item', 'Pokémon Tool', 'Tool', 'Supporter'],
        evolutionStages: ['Basic', 'Stage 1', 'basic'],
      );
      final params = collectionPageParams(
        collectionId: null,
        sort: CardSortOption.priceDesc,
        filters: const CardFilters(
          trainerSubtypes: {TrainerSubtype.tool},
          evolutionStages: {EvolutionStage.basic},
          types: {PokemonType.fire},
          categories: {CardCategory.trainer},
        ),
        facets: facets,
      );

      expect(
        params['p_trainer_subtypes'],
        unorderedEquals(['Pokémon Tool', 'Tool']),
      );
      expect(params['p_evolution_stages'], unorderedEquals(['Basic', 'basic']));
      expect(params['p_types'], ['Fire']);
      expect(params['p_categories'], ['Trainer']);
    });

    test('falls back to the label when the facets have not loaded', () {
      final params = collectionPageParams(
        collectionId: null,
        sort: CardSortOption.priceDesc,
        filters: const CardFilters(trainerSubtypes: {TrainerSubtype.tool}),
      );
      expect(params['p_trainer_subtypes'], ['Pokemon Tool']);
    });
  });

  group('CollectionFacets.toFilterOptions', () {
    test('drops values the chips cannot name', () {
      const facets = CollectionFacets(
        categories: ['Energy', 'Pokemon', 'Sealed', 'Trainer', 'Unknown'],
        types: ['Fire', 'Water', 'Unknown'],
        evolutionStages: ['Basic', 'VMAX'],
        rarities: ['C', 'U', 'SAR'],
      );
      final options = facets.toFilterOptions();

      expect(options.categories, [
        CardCategory.energy,
        CardCategory.pokemon,
        CardCategory.sealed,
        CardCategory.trainer,
      ]);
      expect(options.types, [PokemonType.fire, PokemonType.water]);
      expect(options.evolutionStages, [EvolutionStage.basic]);
      expect(options.rarities, ['C', 'U', 'SAR']);
    });
  });

  test('summary reads the RPC json and knows when it is empty', () {
    final summary = CollectionSummary.fromJson({
      'collection': {'id': 'c1'},
      'total_value': 125000,
      'unique_count': 3,
      'total_count': 5,
      'value_now': 100000,
      'value_7d_ago': 90000,
    });
    expect(summary.totalValue, 125000);
    expect(summary.uniqueCount, 3);
    expect(summary.totalCount, 5);
    expect(summary.isEmpty, isFalse);
    expect(CollectionSummary.empty.isEmpty, isTrue);
  });
}
