import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../repository/models/deck_card_entry.dart';

/// What a deck costs at today's cached prices — the `deckTotal` /
/// `unpricedCount` memo in `deck-panel.tsx`.
class DeckPriceSummary {
  const DeckPriceSummary({
    required this.total,
    required this.unpricedCount,
    required this.rowCount,
  });

  /// Σ price × quantity over the rows that have a price.
  final int total;

  /// Rows with no price at all. Counted per row, not per copy, as on web.
  final int unpricedCount;

  final int rowCount;

  bool get hasAnyPrice => unpricedCount < rowCount;

  /// The figure beside "Total harga": "Rp-" until at least one row is priced.
  String get totalLabel => hasAnyPrice ? formatRupiah(total) : 'Rp-';

  /// "Total harga", with the unpriced count once some rows are priced and
  /// some are not.
  String get caption => unpricedCount > 0 && hasAnyPrice
      ? 'Total harga ($unpricedCount kartu tanpa harga)'
      : 'Total harga';
}

DeckPriceSummary summarizeDeckPrice(List<DeckCardEntry> entries) {
  var total = 0;
  var unpriced = 0;
  for (final entry in entries) {
    final price = entry.card.marketPrice;
    if (price == null) {
      unpriced += 1;
    } else {
      total += price * entry.quantity;
    }
  }
  return DeckPriceSummary(
    total: total,
    unpricedCount: unpriced,
    rowCount: entries.length,
  );
}

/// A deck row's price — the copies it holds, not one — or "Rp-"
/// (`deck-card-row.tsx`).
String deckRowPriceLabel(DeckCardEntry entry) {
  final price = entry.card.marketPrice;
  return price == null ? 'Rp-' : formatRupiah(price * entry.quantity);
}

/// One card's price on a search tile, or "Rp-" (`deck-search-card.tsx`).
String deckSearchPriceLabel(CardModel card) {
  final price = card.marketPrice;
  return price == null ? 'Rp-' : formatRupiah(price);
}
