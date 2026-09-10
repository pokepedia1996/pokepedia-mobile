/// A saved deck, mirroring `public.decks` (+ `deck_cards` for the card
/// count) in `supabase/migrations/00000000000000_baseline.sql`. Ports
/// `UserDeck` from `lib/products/decks.ts`.
class DeckModel {
  const DeckModel({
    required this.id,
    required this.name,
    required this.description,
    required this.shareCode,
    required this.cardCount,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `decks.id` is a uuid, not a serial int.
  final String id;
  final String name;
  final String description;
  final String shareCode;
  final int cardCount;
  final String createdAt;
  final String updatedAt;

  DeckModel copyWith({String? name, String? description}) => DeckModel(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    shareCode: shareCode,
    cardCount: cardCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
