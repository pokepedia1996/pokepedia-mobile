import 'package:intl/intl.dart';

final _rupiahFormat = NumberFormat.decimalPattern('id_ID');
final _compactFormat = NumberFormat.decimalPattern('id_ID')
  ..maximumFractionDigits = 1;

/// Mirrors `formatRupiah` from `lib/utils.ts` on the web.
String formatRupiah(int amount) => 'Rp${_rupiahFormat.format(amount)}';

/// Mirrors `formatRupiahCompact` from `lib/utils/money.ts` — the axis-label
/// form ("Rp12,5rb"), including its two promotion thresholds so 999.950 reads
/// as "Rp1jt" rather than "Rp1.000rb".
String formatRupiahCompact(num amount) {
  if (amount >= 999950000) {
    return 'Rp${_compactFormat.format(amount / 1000000000)}M';
  }
  if (amount >= 999950) {
    return 'Rp${_compactFormat.format(amount / 1000000)}jt';
  }
  if (amount >= 1000) {
    return 'Rp${_compactFormat.format(amount / 1000)}rb';
  }
  return 'Rp${_compactFormat.format(amount)}';
}

/// Mirrors `formatRelativeId` from `lib/marketplace/format-relative.ts`.
/// [now] defaults to the app's fixed dummy "today" so results stay
/// deterministic without a repository/clock dependency.
String formatRelativeId(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime(2026, 7, 16);
  final diff = reference.difference(date);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu lalu';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

const _monthNamesId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Mirrors `formatSaleDate` from `lib/marketplace/format-relative.ts` —
/// "5 Agu 2026", the date column of the sales history table.
String formatSaleDate(DateTime date) =>
    '${date.day} ${_monthNamesId[date.month - 1]} ${date.year}';

/// "5 Agu" — the chart's x-axis / tooltip date label (web's
/// `formatShortDate` in `market-activity-chart.tsx`).
String formatShortDateId(DateTime date) =>
    '${date.day} ${_monthNamesId[date.month - 1]}';

/// "Bergabung {Mon} {yyyy}" — used for a profile's join date.
String formatJoinedId(DateTime date) {
  return 'Bergabung ${_monthNamesId[date.month - 1]} ${date.year}';
}
