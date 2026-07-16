/// A saved deck list (dummy Portfolio > Deck entry).
class DeckModel {
  const DeckModel({
    required this.id,
    required this.name,
    required this.cardCount,
    required this.format,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int cardCount;
  final String format;
  final String updatedAt;
}
