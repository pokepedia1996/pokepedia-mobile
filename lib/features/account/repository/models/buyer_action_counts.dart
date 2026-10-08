/// The buyer's to-do counts — web's `BuyerActionBreakdown` in
/// `contexts/buyer-action-context.tsx`, read from `get_buyer_action_counts`.
///
/// Action-only by design: each count is something the buyer has to do
/// (pay, confirm receipt, answer a proposal or a dispute), never mere status.
class BuyerActionCounts {
  const BuyerActionCounts({
    this.unpaid = 0,
    this.arrived = 0,
    this.proposals = 0,
    this.disputes = 0,
    this.total = 0,
  });

  static const zero = BuyerActionCounts();

  /// Web's `parseBreakdown`: anything that isn't a number reads as zero, and
  /// a payload that isn't an object reads as nothing to do.
  factory BuyerActionCounts.fromJson(Object? raw) {
    if (raw is! Map) return zero;
    int count(Object? value) => value is num ? value.toInt() : 0;
    return BuyerActionCounts(
      unpaid: count(raw['unpaid']),
      arrived: count(raw['arrived']),
      proposals: count(raw['proposals']),
      disputes: count(raw['disputes']),
      total: count(raw['total']),
    );
  }

  final int unpaid;
  final int arrived;
  final int proposals;
  final int disputes;

  /// Server-computed sum, the account-level indicator.
  final int total;

  /// The Pesanan row's badge — web's `ordersCount`, which leaves proposals to
  /// their own row.
  int get orders => unpaid + arrived + disputes;
}
