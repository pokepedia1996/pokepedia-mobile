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
///
/// [now] defaults to the real clock. It used to default to a fixed dummy
/// "today" left over from the seeded-catalog era, which quietly dated every
/// relative stamp in the app — seller offers, inventory activity, dispute
/// events, proposals — against 16 July 2026 instead of the actual date.
/// Tests that want determinism pass [now] themselves.
String formatRelativeId(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(date);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu lalu';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// How long is left, as `CountdownTimer` renders it: days once there is more
/// than one, then hours, then minutes.
///
/// Never negative — a passed deadline reads as "kurang dari 1 menit" rather
/// than counting upward into nonsense.
String formatCountdownId(Duration left) {
  if (left.isNegative || left == Duration.zero) return 'kurang dari 1 menit';
  if (left.inDays >= 1) return '${left.inDays} hari';
  if (left.inHours >= 1) return '${left.inHours} jam';
  if (left.inMinutes >= 1) return '${left.inMinutes} menit';
  return 'kurang dari 1 menit';
}

/// "5 Sep 14:30" — web's `DEADLINE_DATE_FMT`, the stamp on a deadline the
/// buyer or seller has to beat.
String formatDeadlineId(DateTime date) {
  final local = date.toLocal();
  return '${formatShortDateId(local)} ${formatClockId(local)}';
}

/// "14.32" — the clock stamp under a chat bubble.
///
/// A dot, not a colon: web reads this off
/// `toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })`,
/// and Indonesian separates the two with a period. The chat room and the
/// shipment timeline are where both clients show it side by side.
String formatClockId(DateTime date) {
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}.'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// The right-hand stamp on a conversation row — `formatRelativeTime` in
/// `conversation-list.tsx`: "Baru saja" under a minute, then compact minute,
/// hour and day counts, then the day and short month.
String formatChatInboxStamp(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date.toLocal());
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}j';
  if (diff.inDays < 7) return '${diff.inDays}h';
  return formatShortDateId(date.toLocal());
}

/// The clock for today, "Kemarin" for yesterday, the weekday inside the last
/// week, then the date.
String formatChatStamp(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = date.toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysApart = today.difference(day).inDays;

  if (daysApart <= 0) return formatClockId(local);
  if (daysApart == 1) return 'Kemarin';
  if (daysApart < 7) {
    const weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return weekdays[local.weekday - 1];
  }
  return formatShortDateId(local);
}

const _monthNamesId = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
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
