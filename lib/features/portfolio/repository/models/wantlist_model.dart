/// A saved wantlist ("List") — a shareable set of cards a collector is
/// looking for (dummy Portfolio > List entry).
class WantlistModel {
  const WantlistModel({
    required this.id,
    required this.name,
    required this.cardCount,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int cardCount;
  final String updatedAt;
}
