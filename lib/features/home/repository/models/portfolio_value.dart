/// One point on the collection-worth chart: what the whole portfolio was
/// worth at the close of [day].
class PortfolioValuePoint {
  const PortfolioValuePoint({required this.day, required this.value});

  final DateTime day;
  final int value;
}

/// The chart's timeline filter — `1H 7H 1B 3B 6B MAX`.
enum PortfolioRange {
  day(1, '1H'),
  week(7, '7H'),
  month(30, '1B'),
  quarter(90, '3B'),
  half(180, '6B'),
  max(null, 'MAX');

  const PortfolioRange(this.days, this.label);

  /// Null for [PortfolioRange.max] — no lower bound on the query.
  final int? days;
  final String label;

  static const fallback = PortfolioRange.month;
}

/// Which set of cards the header is valuing.
///
/// "Portofolio Utama" is the whole collection (`user_cards`); the rest are
/// the user's saved lists, which is what the app already has that answers to
/// "portofolio yang dimau".
class PortfolioTarget {
  const PortfolioTarget({required this.name, this.listId});

  final String name;

  /// Null for the main collection.
  final String? listId;

  bool get isPrimary => listId == null;

  static const primary = PortfolioTarget(name: 'Utama');

  @override
  bool operator ==(Object other) =>
      other is PortfolioTarget && other.listId == listId;

  @override
  int get hashCode => listId.hashCode;
}

/// A card's contribution to the portfolio, for the "Nilai Tertinggi" list.
class PortfolioHolding {
  const PortfolioHolding({
    required this.cardId,
    required this.name,
    required this.collectorNumber,
    required this.expansionCode,
    required this.rarity,
    required this.packSlug,
    required this.quantity,
    required this.unitPrice,
    this.imageUrl,
  });

  final int cardId;
  final String name;
  final String collectorNumber;
  final String expansionCode;
  final String? rarity;
  final String packSlug;
  final int quantity;
  final int unitPrice;
  final String? imageUrl;

  /// What this line is worth — the number the row shows on the right.
  int get value => unitPrice * quantity;
}
