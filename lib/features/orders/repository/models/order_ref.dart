/// How an `/orders/<ref>` or `/seller/orders/<ref>` link names an order.
///
/// The app addresses an order by `orders.slug`. The website addresses the
/// same screen by *match* — `order_items.slug`, or an order number from
/// either table — and the notification triggers in `supabase/migrations`
/// write all of those shapes into `action_url`. Both slug columns are `uuid`,
/// so a reference has to be classified before it is used in a filter:
/// comparing a uuid column to `ord-260901-a7k3p` is a Postgres error
/// (`22P02`), not an empty result, which is why a tapped notification used to
/// come back as "Gagal memuat pesanan" rather than "tidak ditemukan".
enum OrderRefKind { slug, orderNumber, unknown }

/// The shape both `generate_order_number` and `generate_package_order_number`
/// mint: `ord-` + YYMMDD + a five-character suffix, always stored lowercase.
final _orderNumberPattern = RegExp(
  r'^ord-\d{6}-[0-9a-z]{5}$',
  caseSensitive: false,
);

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

OrderRefKind classifyOrderRef(String ref) {
  final needle = ref.trim();
  if (_uuidPattern.hasMatch(needle)) return OrderRefKind.slug;
  if (_orderNumberPattern.hasMatch(needle)) return OrderRefKind.orderNumber;
  return OrderRefKind.unknown;
}
