import '../../../shared/models/card_model.dart';
import '../../../shared/utils/collector_number.dart';
import '../../../shared/utils/csv_export.dart';
import '../../../shared/utils/variant_label.dart';
import '../repository/models/portfolio_export_row.dart';

/// The portfolio export: every card on every portfolio, in one CSV, with a
/// Portofolio column saying whose shelf each row is on. Web has no export
/// to port; this is the app's own.

/// [rows] as CSV: each portfolio together, Utama first then the lists in
/// the app's order, and within one the cards by expansion and number — the
/// order a binder runs in.
///
/// Prices are bare rupiah so a spreadsheet can add them up; a card with no
/// market price leaves both price cells empty rather than reading as free.
String portfolioCsv(List<PortfolioExportRow> rows) {
  final sorted = [...rows]
    ..sort((a, b) {
      final byPortfolio = a.portfolioIndex.compareTo(b.portfolioIndex);
      if (byPortfolio != 0) return byPortfolio;
      final byExpansion = a.card.expansionCode.toLowerCase().compareTo(
        b.card.expansionCode.toLowerCase(),
      );
      if (byExpansion != 0) return byExpansion;
      return compareCollectorNumber(
        a.card.collectorNumber,
        b.card.collectorNumber,
      );
    });

  return csvDocument([
    const [
      'Portofolio',
      'Nama Kartu',
      'Varian',
      'Bahasa',
      'Ekspansi',
      'Nomor',
      'Kelangkaan',
      'Seri',
      'Jumlah',
      'Harga Pasar',
      'Nilai Total',
      'Catatan',
    ],
    for (final r in sorted)
      [
        csvText(r.portfolio),
        csvText(r.card.name),
        csvText(formatCardVariant(r.variantKey ?? r.card.variant) ?? ''),
        r.card.language.shortLabel,
        csvText(r.card.expansionCode.toUpperCase()),
        csvText(stripCardNumberSuffix(r.card.collectorNumber)),
        csvText(r.card.rarity ?? ''),
        csvText(r.series ?? ''),
        '${r.quantity}',
        if (r.card.marketPrice case final price?) ...[
          '$price',
          '${price * r.quantity}',
        ] else ...[
          '',
          '',
        ],
        csvText(r.notes?.trim() ?? ''),
      ],
  ]);
}

/// `pokepedia-portofolio-2026-10-21.csv`.
String portfolioExportFileName({DateTime? now}) =>
    'pokepedia-portofolio-${csvDay(now ?? DateTime.now())}.csv';
