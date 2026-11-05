import 'package:flutter/material.dart';

import '../../../shared/utils/collector_number.dart';
import '../../../shared/utils/csv_export.dart';
import '../../../shared/utils/variant_label.dart';
import '../repository/models/inventory_entry.dart';

/// The Aktivitas tab's export: the trail between two days, as a CSV a
/// spreadsheet opens. Web has no export to port; this is the app's own.

/// The rows of [rows] from the start of [range]'s first day to the end of
/// its last, in the phone's time zone — every row when [range] is null.
List<InventoryActivityEntry> activityInRange(
  List<InventoryActivityEntry> rows,
  DateTimeRange? range,
) {
  if (range == null) return rows;
  final from = DateUtils.dateOnly(range.start);
  final until = DateUtils.dateOnly(range.end).add(const Duration(days: 1));
  return [
    for (final r in rows)
      if (!r.createdAt.toLocal().isBefore(from) &&
          r.createdAt.toLocal().isBefore(until))
        r,
  ];
}

/// [rows] as CSV, a line per row in the order given.
///
/// Prices are bare rupiah, not "Rp1.000", so a spreadsheet can add them up.
String activityCsv(List<InventoryActivityEntry> rows) => csvDocument([
  const [
    'Tanggal',
    'Aksi',
    'Jumlah',
    'Nama Kartu',
    'Varian',
    'Ekspansi',
    'Nomor',
    'Kelangkaan',
    'Seri',
    'Harga Satuan',
    'Harga Total',
  ],
  for (final r in rows)
    [
      csvStamp(r.createdAt.toLocal()),
      r.action.label,
      '${r.quantity}',
      csvText(r.card.name),
      csvText(formatCardVariant(r.variantKey ?? r.card.variant) ?? ''),
      csvText(r.card.expansionCode.toUpperCase()),
      csvText(stripCardNumberSuffix(r.card.collectorNumber)),
      csvText(r.card.rarity ?? ''),
      csvText(r.series ?? ''),
      '${r.unitPrice}',
      '${r.unitPrice * r.quantity}',
    ],
]);

/// `pokepedia-aktivitas-2026-09-01_2026-09-30.csv`, or for everything,
/// `pokepedia-aktivitas-semua-<today>.csv`.
String activityExportFileName(DateTimeRange? range, {DateTime? now}) {
  if (range == null) {
    return 'pokepedia-aktivitas-semua-${csvDay(now ?? DateTime.now())}.csv';
  }
  return 'pokepedia-aktivitas-${csvDay(range.start)}_${csvDay(range.end)}.csv';
}
