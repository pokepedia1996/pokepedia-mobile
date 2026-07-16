/// Pokemon TCG energy types. Mirrors the 12 icon assets shipped under
/// `pokepedia-web/public/elements/` (also bundled here at
/// `assets/images/elements/`) and the `weakness`/`resistance`/attack-cost
/// type values stored in `cards.details` (see
/// `supabase/migrations/00000000000000_baseline.sql`).
enum PokemonType {
  colorless,
  darkness,
  dragon,
  fairy,
  fighting,
  fire,
  grass,
  lightning,
  metal,
  prism,
  psychic,
  water,
}

extension PokemonTypeX on PokemonType {
  /// Matches the asset filename / `details` jsonb value casing exactly.
  String get assetName {
    switch (this) {
      case PokemonType.colorless:
        return 'Colorless';
      case PokemonType.darkness:
        return 'Darkness';
      case PokemonType.dragon:
        return 'Dragon';
      case PokemonType.fairy:
        return 'Fairy';
      case PokemonType.fighting:
        return 'Fighting';
      case PokemonType.fire:
        return 'Fire';
      case PokemonType.grass:
        return 'Grass';
      case PokemonType.lightning:
        return 'Lightning';
      case PokemonType.metal:
        return 'Metal';
      case PokemonType.prism:
        return 'Prism';
      case PokemonType.psychic:
        return 'Psychic';
      case PokemonType.water:
        return 'Water';
    }
  }

  String get iconAsset => 'assets/images/elements/$assetName.webp';

  String get labelId {
    switch (this) {
      case PokemonType.colorless:
        return 'Colorless';
      case PokemonType.darkness:
        return 'Kegelapan';
      case PokemonType.dragon:
        return 'Naga';
      case PokemonType.fairy:
        return 'Fairy';
      case PokemonType.fighting:
        return 'Petarung';
      case PokemonType.fire:
        return 'Api';
      case PokemonType.grass:
        return 'Rumput';
      case PokemonType.lightning:
        return 'Petir';
      case PokemonType.metal:
        return 'Logam';
      case PokemonType.prism:
        return 'Prisma';
      case PokemonType.psychic:
        return 'Psikis';
      case PokemonType.water:
        return 'Air';
    }
  }
}
