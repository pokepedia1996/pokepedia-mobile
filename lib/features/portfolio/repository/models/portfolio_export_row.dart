import '../../../../shared/models/card_model.dart';

/// One card on one portfolio's shelf, for the portfolio export — a
/// `collection_cards` row with its card, priced.
class PortfolioExportRow {
  const PortfolioExportRow({
    required this.portfolio,
    required this.portfolioIndex,
    required this.card,
    required this.quantity,
    this.variantKey,
    this.series,
    this.notes,
  });

  /// The portfolio's name: "Utama" for the main collection, else the list's.
  final String portfolio;

  /// Where the portfolio sits in the app's own order — 0 for Utama, then the
  /// lists as the picker shows them — so the file keeps each one together
  /// even when two lists share a name.
  final int portfolioIndex;

  /// The card, with its market price on it where one is known.
  final CardModel card;
  final int quantity;
  final String? variantKey;
  final String? series;
  final String? notes;
}
