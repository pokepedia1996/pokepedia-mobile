import 'package:intl/intl.dart';

final _rupiahFormat = NumberFormat.decimalPattern('id_ID');

/// Mirrors `formatRupiah` from `lib/utils.ts` on the web.
String formatRupiah(int amount) => 'Rp${_rupiahFormat.format(amount)}';

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
