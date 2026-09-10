import '../models/card_model.dart';
import '../models/pokemon_type.dart';

/// A curated pool of real Pokemon with plausible TCG-accurate typing, used
/// to generate schema-shaped dummy `cards.details` data (see
/// `CardDetails` / `supabase/migrations/00000000000000_baseline.sql`).
/// Attack names/damage are illustrative, not lifted from real print runs.
class PokemonSpecies {
  const PokemonSpecies({
    required this.name,
    required this.types,
    required this.hp,
    required this.evolutionStage,
    required this.retreatCost,
    required this.attacks,
    required this.weaknessType,
    this.evolvesFrom,
  });

  final String name;
  final List<PokemonType> types;
  final int hp;
  final EvolutionStage evolutionStage;
  final int retreatCost;
  final List<AttackModel> attacks;
  final PokemonType weaknessType;
  final String? evolvesFrom;

  static const pool = <PokemonSpecies>[
    PokemonSpecies(
      name: 'Pikachu',
      types: [PokemonType.lightning],
      hp: 70,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Thunder Shock',
          cost: [PokemonType.lightning],
          damage: '30',
        ),
        AttackModel(
          name: 'Agility',
          cost: [PokemonType.lightning, PokemonType.colorless],
          damage: '10',
          effect:
              'Lempar koin, jika sisi kepala, hindari serangan lawan berikutnya.',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Raichu',
      evolvesFrom: 'Pikachu',
      types: [PokemonType.lightning],
      hp: 120,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Thunder Punch',
          cost: [PokemonType.lightning, PokemonType.colorless],
          damage: '70',
          effect: 'Lempar koin, jika sisi ekor, Raichu terkena 20 damage.',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Charmander',
      types: [PokemonType.fire],
      hp: 60,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(name: 'Ember', cost: [PokemonType.fire], damage: '20'),
      ],
      weaknessType: PokemonType.water,
    ),
    PokemonSpecies(
      name: 'Charizard',
      evolvesFrom: 'Charmeleon',
      types: [PokemonType.fire],
      hp: 180,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 3,
      attacks: [
        AttackModel(
          name: 'Fire Spin',
          cost: [PokemonType.fire, PokemonType.fire, PokemonType.colorless],
          damage: '100',
          effect: 'Buang 2 Energy yang terpasang.',
        ),
      ],
      weaknessType: PokemonType.water,
    ),
    PokemonSpecies(
      name: 'Bulbasaur',
      types: [PokemonType.grass],
      hp: 70,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Vine Whip',
          cost: [PokemonType.grass, PokemonType.colorless],
          damage: '40',
        ),
      ],
      weaknessType: PokemonType.fire,
    ),
    PokemonSpecies(
      name: 'Venusaur',
      evolvesFrom: 'Ivysaur',
      types: [PokemonType.grass],
      hp: 190,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 3,
      attacks: [
        AttackModel(
          name: 'Giant Bloom',
          cost: [PokemonType.grass, PokemonType.grass, PokemonType.colorless],
          damage: '110',
          effect: 'Pulihkan 30 damage dari Pokemon ini.',
        ),
      ],
      weaknessType: PokemonType.fire,
    ),
    PokemonSpecies(
      name: 'Squirtle',
      types: [PokemonType.water],
      hp: 60,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Bubble',
          cost: [PokemonType.water],
          damage: '20',
          effect: 'Lawan mungkin lumpuh (paralyzed).',
        ),
      ],
      weaknessType: PokemonType.lightning,
    ),
    PokemonSpecies(
      name: 'Blastoise',
      evolvesFrom: 'Wartortle',
      types: [PokemonType.water],
      hp: 180,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 3,
      attacks: [
        AttackModel(
          name: 'Hydro Pump',
          cost: [PokemonType.water, PokemonType.water, PokemonType.colorless],
          damage: '90',
          effect: '+30 damage untuk setiap Water Energy tambahan.',
        ),
      ],
      weaknessType: PokemonType.lightning,
    ),
    PokemonSpecies(
      name: 'Eevee',
      types: [PokemonType.colorless],
      hp: 70,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Tackle',
          cost: [PokemonType.colorless],
          damage: '20',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Sylveon',
      evolvesFrom: 'Eevee',
      types: [PokemonType.fairy],
      hp: 130,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Moonlight Ribbon',
          cost: [PokemonType.fairy, PokemonType.colorless],
          damage: '60',
          effect: 'Pulihkan 30 damage dari Pokemon ini.',
        ),
      ],
      weaknessType: PokemonType.metal,
    ),
    PokemonSpecies(
      name: 'Umbreon',
      evolvesFrom: 'Eevee',
      types: [PokemonType.darkness],
      hp: 140,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Feint Attack',
          cost: [PokemonType.darkness, PokemonType.colorless],
          damage: '70',
          effect: 'Serangan ini mengabaikan efek pada Pokemon Bertahan.',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Espeon',
      evolvesFrom: 'Eevee',
      types: [PokemonType.psychic],
      hp: 130,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Psybeam',
          cost: [PokemonType.psychic, PokemonType.colorless],
          damage: '50',
          effect: 'Lempar koin, jika sisi kepala, lawan bingung (confused).',
        ),
      ],
      weaknessType: PokemonType.darkness,
    ),
    PokemonSpecies(
      name: 'Mewtwo',
      types: [PokemonType.psychic],
      hp: 160,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 2,
      attacks: [
        AttackModel(
          name: 'Psystrike',
          cost: [
            PokemonType.psychic,
            PokemonType.psychic,
            PokemonType.colorless,
          ],
          damage: '120',
        ),
      ],
      weaknessType: PokemonType.darkness,
    ),
    PokemonSpecies(
      name: 'Gengar',
      evolvesFrom: 'Haunter',
      types: [PokemonType.psychic],
      hp: 150,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Shadow Bind',
          cost: [PokemonType.psychic, PokemonType.colorless],
          damage: '60',
          effect: 'Pokemon Bertahan tidak bisa retreat di giliran berikutnya.',
        ),
      ],
      weaknessType: PokemonType.darkness,
    ),
    PokemonSpecies(
      name: 'Snorlax',
      types: [PokemonType.colorless],
      hp: 170,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 4,
      attacks: [
        AttackModel(
          name: 'Body Slam',
          cost: [
            PokemonType.colorless,
            PokemonType.colorless,
            PokemonType.colorless,
          ],
          damage: '80',
          effect: 'Lempar koin, jika sisi kepala, lawan lumpuh (paralyzed).',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Lucario',
      types: [PokemonType.fighting],
      hp: 120,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Aura Sphere',
          cost: [PokemonType.fighting, PokemonType.colorless],
          damage: '60',
        ),
      ],
      weaknessType: PokemonType.psychic,
    ),
    PokemonSpecies(
      name: 'Greninja',
      evolvesFrom: 'Frogadier',
      types: [PokemonType.water],
      hp: 130,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Water Shuriken',
          cost: [PokemonType.water],
          damage: '30',
          effect: '+30 damage untuk setiap Water Energy tambahan.',
        ),
      ],
      weaknessType: PokemonType.lightning,
    ),
    PokemonSpecies(
      name: 'Rayquaza',
      types: [PokemonType.dragon],
      hp: 180,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 2,
      attacks: [
        AttackModel(
          name: 'Dragon Break',
          cost: [
            PokemonType.lightning,
            PokemonType.fighting,
            PokemonType.colorless,
          ],
          damage: '130',
        ),
      ],
      weaknessType: PokemonType.fairy,
    ),
    PokemonSpecies(
      name: 'Gyarados',
      evolvesFrom: 'Magikarp',
      types: [PokemonType.water],
      hp: 160,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 3,
      attacks: [
        AttackModel(
          name: 'Dragon Tail',
          cost: [PokemonType.water, PokemonType.water, PokemonType.colorless],
          damage: '90',
        ),
      ],
      weaknessType: PokemonType.lightning,
    ),
    PokemonSpecies(
      name: 'Dragonite',
      evolvesFrom: 'Dragonair',
      types: [PokemonType.dragon],
      hp: 170,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 2,
      attacks: [
        AttackModel(
          name: 'Hyper Beam',
          cost: [
            PokemonType.colorless,
            PokemonType.colorless,
            PokemonType.colorless,
            PokemonType.colorless,
          ],
          damage: '150',
        ),
      ],
      weaknessType: PokemonType.fairy,
    ),
    PokemonSpecies(
      name: 'Absol',
      types: [PokemonType.darkness],
      hp: 110,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Feint Slash',
          cost: [PokemonType.darkness, PokemonType.colorless],
          damage: '60',
        ),
      ],
      weaknessType: PokemonType.fighting,
    ),
    PokemonSpecies(
      name: 'Garchomp',
      evolvesFrom: 'Gabite',
      types: [PokemonType.dragon],
      hp: 170,
      evolutionStage: EvolutionStage.stage2,
      retreatCost: 2,
      attacks: [
        AttackModel(
          name: 'Dragon Claw',
          cost: [PokemonType.dragon, PokemonType.colorless],
          damage: '100',
        ),
      ],
      weaknessType: PokemonType.fairy,
    ),
    PokemonSpecies(
      name: 'Lapras',
      types: [PokemonType.water],
      hp: 150,
      evolutionStage: EvolutionStage.basic,
      retreatCost: 3,
      attacks: [
        AttackModel(
          name: 'Ice Beam',
          cost: [PokemonType.water, PokemonType.colorless],
          damage: '70',
          effect: 'Lempar koin, jika sisi kepala, lawan lumpuh (paralyzed).',
        ),
      ],
      weaknessType: PokemonType.lightning,
    ),
    PokemonSpecies(
      name: 'Ninetales',
      evolvesFrom: 'Vulpix',
      types: [PokemonType.fire],
      hp: 130,
      evolutionStage: EvolutionStage.stage1,
      retreatCost: 1,
      attacks: [
        AttackModel(
          name: 'Fire Blast',
          cost: [PokemonType.fire, PokemonType.fire, PokemonType.colorless],
          damage: '90',
          effect: 'Buang Energy Api dari Pokemon ini.',
        ),
      ],
      weaknessType: PokemonType.water,
    ),
  ];
}

const trainerCardNames = <(String, TrainerSubtype)>[
  ('Professor\'s Research', TrainerSubtype.supporter),
  ("Boss's Orders", TrainerSubtype.supporter),
  ('Iono', TrainerSubtype.supporter),
  ('Ultra Ball', TrainerSubtype.item),
  ('Nest Ball', TrainerSubtype.item),
  ('Rare Candy', TrainerSubtype.item),
  ('Switch', TrainerSubtype.item),
  ("Trainer's Toolbox", TrainerSubtype.tool),
  ('Choice Belt', TrainerSubtype.tool),
  ('Path to the Peak', TrainerSubtype.stadium),
];

const energyCardTypes = <PokemonType>[
  PokemonType.fire,
  PokemonType.water,
  PokemonType.grass,
  PokemonType.lightning,
  PokemonType.psychic,
  PokemonType.fighting,
  PokemonType.darkness,
  PokemonType.metal,
];
