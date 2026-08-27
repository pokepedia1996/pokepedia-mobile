import '../models/card_condition.dart';
import '../models/card_model.dart';
import '../models/listing_model.dart';
import '../models/pack_model.dart';
import '../models/pokemon_type.dart';
import '../models/store_model.dart';
import 'pokemon_species.dart';

/// Single source of dummy catalog data shared across every feature's
/// repository layer. Cards/packs/listings/stores are shaped after the real
/// tables in `supabase/migrations/00000000000000_baseline.sql` (`cards`,
/// `expansions`, `series`, `listings`, `seller_profiles`) — this still
/// stands in for the real Supabase-backed catalog while this pass only
/// ports the UI, no repository/API calls are made against it.
class DummyCatalog {
  DummyCatalog._();

  static const _rarities = [
    'Common',
    'Uncommon',
    'Rare',
    'Rare Holo',
    'Double Rare',
    'Ultra Rare',
    'Illustration Rare',
    'Hyper Rare',
  ];

  static const _regulationMarks = ['G', 'H', 'I'];
  static const _illustrators = [
    'Mitsuhiro Arita',
    'Ken Sugimori',
    '5ban Graphics',
    'PLANETA Mochizuki',
    'Naoki Saito',
  ];

  static const _seriesDefs = [
    ('Scarlet & Violet', 'SV'),
    ('Sword & Shield', 'SWSH'),
    ('Sun & Moon', 'SM'),
  ];

  static const _packNamesBySeries = {
    'Scarlet & Violet': ['Obsidian Flames', 'Paldea Evolved', 'Paradox Rift'],
    'Sword & Shield': ['Evolving Skies', 'Brilliant Stars', 'Astral Radiance'],
    'Sun & Moon': ['Team Up', 'Unbroken Bonds', 'Cosmic Eclipse'],
  };

  static final List<SeriesGroup> seriesGroups = _buildSeries();
  static final List<PackModel> packs = seriesGroups
      .expand((g) => g.packs)
      .toList();
  static final Map<String, List<CardModel>> cardsByPack = _buildCards();
  static final List<CardModel> allCards = cardsByPack.values
      .expand((c) => c)
      .toList();
  static final List<StoreModel> stores = _buildStores();
  static final List<ListingModel> listings = _buildListings();

  static List<SeriesGroup> _buildSeries() {
    final groups = <SeriesGroup>[];
    var releaseYear = 2024;
    for (final (series, mark) in _seriesDefs) {
      final names = _packNamesBySeries[series]!;
      final packsForSeries = <PackModel>[];
      for (var i = 0; i < names.length; i++) {
        final cardCount = 60 + (i * 15) % 40;
        final collected = (cardCount * (0.15 + 0.1 * i)).round();
        packsForSeries.add(
          PackModel(
            slug: '${_slugify(mark)}-${_slugify(names[i])}',
            name: names[i],
            mark: '$mark${i + 1}',
            series: series,
            releaseDate:
                '${releaseYear - i} ${['Jan', 'Apr', 'Aug', 'Nov'][i % 4]}',
            cardCount: cardCount,
            productType: i == names.length - 1 ? 'Special Set' : 'Expansion',
            collectedCount: collected,
          ),
        );
      }
      groups.add(SeriesGroup(series: series, packs: packsForSeries));
      releaseYear -= 2;
    }
    return groups;
  }

  /// Card category mix roughly matching a real TCG set: ~60% Pokemon,
  /// ~30% Trainer, ~10% Energy.
  static Map<String, List<CardModel>> _buildCards() {
    final map = <String, List<CardModel>>{};
    var globalId = 1;
    for (final pack in packs) {
      final cards = <CardModel>[];
      for (var i = 0; i < pack.cardCount; i++) {
        final slot = i % 10;
        final CardModel card;
        if (slot < 6) {
          card = _buildPokemonCard(globalId, i, pack);
        } else if (slot < 9) {
          card = _buildTrainerCard(globalId, i, pack);
        } else {
          card = _buildEnergyCard(globalId, i, pack);
        }
        cards.add(card);
        globalId++;
      }
      map[pack.slug] = cards;
    }
    return map;
  }

  static CardModel _buildPokemonCard(int id, int i, PackModel pack) {
    final species = PokemonSpecies.pool[id % PokemonSpecies.pool.length];
    final rarity = _rarities[id % _rarities.length];
    return CardModel(
      id: id,
      category: CardCategory.pokemon,
      nameId: species.evolvesFrom != null && id % 3 == 0
          ? '${species.name} ex'
          : species.name,
      expansionCode: pack.mark,
      packSlug: pack.slug,
      collectorNumber: '${i + 1}/${pack.cardCount}',
      rarity: rarity,
      regulationMark: _regulationMarks[id % _regulationMarks.length],
      illustrator: _illustrators[id % _illustrators.length],
      details: CardDetails(
        hp: species.hp,
        pokemonTypes: species.types,
        evolutionStage: species.evolutionStage,
        evolvesFrom: species.evolvesFrom,
        attacks: species.attacks,
        weakness: TypeModifier(type: species.weaknessType, value: '+20'),
        retreatCost: species.retreatCost,
      ),
      marketPrice: 5000 + ((id * 3733) % 480000),
      owned: i < pack.collectedCount ? 1 + (i % 3) : 0,
    );
  }

  static CardModel _buildTrainerCard(int id, int i, PackModel pack) {
    final (name, subtype) = trainerCardNames[id % trainerCardNames.length];
    return CardModel(
      id: id,
      category: CardCategory.trainer,
      nameId: name,
      expansionCode: pack.mark,
      packSlug: pack.slug,
      collectorNumber: '${i + 1}/${pack.cardCount}',
      rarity: id % 5 == 0 ? 'Ultra Rare' : 'Uncommon',
      illustrator: _illustrators[id % _illustrators.length],
      details: CardDetails(trainerSubtype: subtype),
      marketPrice: 3000 + ((id * 2917) % 120000),
      owned: i < pack.collectedCount ? 1 + (i % 3) : 0,
    );
  }

  static CardModel _buildEnergyCard(int id, int i, PackModel pack) {
    final type = energyCardTypes[id % energyCardTypes.length];
    return CardModel(
      id: id,
      category: CardCategory.energy,
      nameId: '${type.labelId} Energy',
      expansionCode: pack.mark,
      packSlug: pack.slug,
      collectorNumber: '${i + 1}/${pack.cardCount}',
      rarity: 'Common',
      details: CardDetails(energyType: type),
      marketPrice: 1000 + ((id * 977) % 8000),
      owned: i < pack.collectedCount ? 1 + (i % 4) : 0,
    );
  }

  static const _cities = [
    'Jakarta Selatan',
    'Bandung',
    'Surabaya',
    'Yogyakarta',
    'Medan',
    'Semarang',
  ];

  static const _storeHandles = [
    ('cardvault.id', 'Card Vault ID', 'Grading & slab specialist', true, true),
    ('pokecorner', 'Poke Corner', 'Booster box & singles', true, false),
    ('trainerhub', 'Trainer Hub', 'Vintage WOTC collector', false, false),
    ('gxstore', 'GX Store', 'Fast response, COD area Jabodetabek', true, false),
    (
      'holofoil.id',
      'Holofoil.id',
      'Jual beli kartu holo & rainbow',
      false,
      false,
    ),
  ];

  static List<StoreModel> _buildStores() {
    return List.generate(_storeHandles.length, (i) {
      final (handle, name, tagline, verified, topRated) = _storeHandles[i];
      return StoreModel(
        handle: handle,
        storeName: name,
        tagline: tagline,
        activeListingCount: 20 + i * 17,
        cityName: _cities[i % _cities.length],
        isVerified: verified,
        topRated: topRated,
        itemsSoldCount: 80 + i * 63,
        followersCount: 30 + i * 41,
        vacationMode: i == 4 ? 'soft' : null,
      );
    });
  }

  static List<ListingModel> _buildListings() {
    final result = <ListingModel>[];
    final now = DateTime(2026, 7, 16);
    var id = 1;
    for (var i = 0; i < allCards.length; i += 3) {
      final card = allCards[i];
      final store = stores[i % stores.length];
      final side = i % 5 == 0 ? ListingSide.bid : ListingSide.ask;
      final condition = i % 7 == 0
          ? CardCondition.psa10
          : i % 11 == 0
          ? CardCondition.psa9
          : CardCondition.values[i % rawConditions.length];
      final quantity = 1 + (i % 6);
      result.add(
        ListingModel(
          id: id,
          slug: 'lst-${id.toString().padLeft(6, '0')}',
          side: side,
          price: card.marketPrice ?? 25000,
          condition: condition,
          quantity: quantity,
          qtyLocked: i % 8 == 0 ? 1 : 0,
          card: card,
          storeSlug: store.handle,
          storeName: store.storeName,
          isVerified: store.isVerified,
          cityName: store.cityName,
          createdAt: now.subtract(Duration(hours: i * 3 + 1)),
          acceptsOffers: i % 4 == 0,
          isFeatured: i % 9 == 0,
          viewCount: 12 + (i * 7) % 340,
        ),
      );
      id++;
      if (result.length >= 60) break;
    }
    return result;
  }

  static String _slugify(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  static PackModel? packBySlug(String slug) {
    for (final p in packs) {
      if (p.slug == slug) return p;
    }
    return null;
  }

  static CardModel? cardById(int id) {
    for (final c in allCards) {
      if (c.id == id) return c;
    }
    return null;
  }
}
