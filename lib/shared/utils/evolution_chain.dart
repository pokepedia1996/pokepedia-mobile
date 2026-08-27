import '../models/card_model.dart';

/// Ports `EvolutionCardInfo` from `lib/utils/index.tsx`.
class EvolutionCardInfo {
  const EvolutionCardInfo({
    required this.name,
    required this.cardId,
    required this.packSlug,
    this.imageUrl,
    this.pokedexNumber,
  });

  final String name;
  final int cardId;
  final String packSlug;
  final String? imageUrl;
  final int? pokedexNumber;
}

/// Ports `EvolutionStage` (renamed to avoid clashing with the
/// `EvolutionStage` enum on [CardDetails]).
class EvolutionStageGroup {
  const EvolutionStageGroup(this.cards);

  final List<EvolutionCardInfo> cards;
}

/// Ports `buildEvolutionStages` from `lib/cards/evolution.ts` — walks
/// [pool] (every card reachable from [current] via `evolves_from` in
/// either direction) back to the root of the line, then breadth-first
/// forward from the root to group cards into stages. Returns null when
/// there's nothing to show (a single-stage "evolution").
///
/// [current] is prepended to [pool] rather than only being used for its
/// name, which is a deliberate divergence from the web. `get_evolution_pool`
/// collapses each species to one row with `DISTINCT ON (name_id)`, and the
/// row that survives is whichever print has the lowest id — not necessarily
/// the card being viewed, and old prints often carry no `evolves_from` at
/// all. Web looks the species up in that pool (`nameToFirst.get(rootName)`)
/// and so walks up from a row that may not know its own parent: the root
/// resolves to the card itself, nothing evolves from it, one stage comes
/// back and the section silently disappears. Real case: Beedrill's pool row
/// is id 339 with a null `evolves_from`, which hides the whole
/// Weedle → Kakuna → Beedrill line. Putting [current] first means its own
/// `evolves_from` edge is in the graph, its row wins for its own species,
/// and the stage chip shows the print the user is actually looking at.
List<EvolutionStageGroup>? buildEvolutionStages(
  CardModel current,
  List<CardModel> pool,
) {
  final allCards = [
    current,
    ...pool.where((c) => c.id != current.id),
  ].where((c) => c.category == CardCategory.pokemon).toList();

  final nameToFirst = <String, CardModel>{};
  for (final c in allCards) {
    nameToFirst.putIfAbsent(c.name, () => c);
  }

  final forwardMap = <String, List<String>>{};
  for (final c in allCards) {
    final from = c.details.evolvesFrom;
    if (from == null) continue;
    final list = forwardMap.putIfAbsent(from, () => []);
    if (!list.contains(c.name)) list.add(c.name);
  }

  var rootName = current.name;
  final seen = <String>{rootName};
  var cursor = nameToFirst[rootName];
  while (cursor?.details.evolvesFrom != null) {
    final from = cursor!.details.evolvesFrom!;
    if (seen.contains(from)) break;
    final parent = nameToFirst[from];
    if (parent == null) break;
    rootName = parent.name;
    seen.add(rootName);
    cursor = parent;
  }

  final cardPool = <String, EvolutionCardInfo>{};
  for (final c in allCards) {
    cardPool.putIfAbsent(
      c.name,
      () => EvolutionCardInfo(
        name: c.name,
        cardId: c.id,
        packSlug: c.packSlug,
        imageUrl: c.imageUrl,
        pokedexNumber: c.details.pokedexNumber,
      ),
    );
  }

  final stages = <EvolutionStageGroup>[];
  var queue = [rootName];
  final visited = <String>{};

  while (queue.isNotEmpty) {
    final stageCards = <EvolutionCardInfo>[];
    final nextQueue = <String>[];

    for (final name in queue) {
      if (visited.contains(name)) continue;
      visited.add(name);
      final card = cardPool[name];
      if (card != null) stageCards.add(card);
      final successors = forwardMap[name];
      if (successors != null) {
        for (final s in successors) {
          if (!visited.contains(s)) nextQueue.add(s);
        }
      }
    }

    if (stageCards.isNotEmpty) {
      stageCards.sort((a, b) => a.name.compareTo(b.name));
      stages.add(EvolutionStageGroup(stageCards));
    }
    queue = nextQueue;
  }

  return stages.length > 1 ? stages : null;
}

const _pokeapiSpriteBase =
    'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon';

/// Ports `getPokemonSpriteUrl` (minus the mega-evolution form-id overrides
/// table, which only affects a handful of names).
String? pokemonSpriteUrl(int? pokedexNumber) {
  if (pokedexNumber == null) return null;
  return '$_pokeapiSpriteBase/$pokedexNumber.png';
}
