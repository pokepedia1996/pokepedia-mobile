/// Ports `features/seller/domain/my-reliability.ts` and the parts of
/// `reliability.ts` the dashboard draws: the seller's own reliability over
/// 90 and 30 days, from `get_my_reliability`.
class ReliabilityWindow {
  const ReliabilityWindow({
    this.paidOrders = 0,
    this.completedOrders = 0,
    this.sellerCancels = 0,
    this.disputesLost = 0,
    this.shippedOrders = 0,
    this.medianShipHours,
  });

  factory ReliabilityWindow.fromJson(Map<String, dynamic> json) =>
      ReliabilityWindow(
        paidOrders: (json['paid_orders'] as num?)?.toInt() ?? 0,
        completedOrders: (json['completed_orders'] as num?)?.toInt() ?? 0,
        sellerCancels: (json['seller_cancels'] as num?)?.toInt() ?? 0,
        disputesLost: (json['disputes_lost'] as num?)?.toInt() ?? 0,
        shippedOrders: (json['shipped_orders'] as num?)?.toInt() ?? 0,
        medianShipHours: (json['median_ship_hours'] as num?)?.toDouble(),
      );

  final int paidOrders;
  final int completedOrders;
  final int sellerCancels;
  final int disputesLost;
  final int shippedOrders;
  final double? medianShipHours;

  /// Web's `describeReliability(...).completionPct`: null until there are
  /// enough paid orders for the share to mean anything.
  int? get publicCompletionPct {
    if (paidOrders < MyReliability.minOrdersForPublicMetrics) return null;
    final finished = completedOrders + sellerCancels + disputesLost;
    return finished > 0 ? completedOrders * 100 ~/ finished : null;
  }

  /// Median hours to ship, rounded up — web publishes it once enough
  /// orders have both been paid and shipped.
  int? get publicShipHours {
    final hours = medianShipHours;
    if (hours == null ||
        paidOrders < MyReliability.minOrdersForPublicMetrics ||
        shippedOrders < MyReliability.minOrdersForPublicMetrics) {
      return null;
    }
    return hours.ceil().clamp(1, 1 << 30);
  }
}

enum ReliabilityFault { expired, cancelled, disputeLost }

/// An order counted against the seller in the last 90 days.
class ReliabilityFailure {
  const ReliabilityFailure({
    required this.orderNumber,
    required this.fault,
    required this.itemSlug,
  });

  final String orderNumber;
  final ReliabilityFault fault;
  final String itemSlug;

  String get faultLabel => switch (fault) {
    ReliabilityFault.expired => 'Lewat batas kirim',
    ReliabilityFault.cancelled => 'Dibatalkan penjual',
    ReliabilityFault.disputeLost => 'Komplain kalah',
  };
}

class MyReliability {
  const MyReliability({
    required this.window90d,
    required this.window30d,
    required this.topRated,
    required this.negativeRating30d,
    this.failures = const [],
  });

  /// Null for the RPC's `{error: ...}` answer or a shape it doesn't know.
  static MyReliability? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final w90 = json['window_90d'];
    final w30 = json['window_30d'];
    if (w90 is! Map<String, dynamic> || w30 is! Map<String, dynamic>) {
      return null;
    }
    return MyReliability(
      window90d: ReliabilityWindow.fromJson(w90),
      window30d: ReliabilityWindow.fromJson(w30),
      topRated: json['top_rated'] == true,
      negativeRating30d: json['negative_rating_30d'] == true,
      failures: [
        for (final f in (json['failures'] as List? ?? const []))
          if (f is Map<String, dynamic> && _fault(f['fault']) != null)
            ReliabilityFailure(
              orderNumber: '${f['order_number']}',
              fault: _fault(f['fault'])!,
              itemSlug: '${f['item_slug']}',
            ),
      ],
    );
  }

  static ReliabilityFault? _fault(Object? value) => switch (value) {
    'expired' => ReliabilityFault.expired,
    'cancelled' => ReliabilityFault.cancelled,
    'dispute_lost' => ReliabilityFault.disputeLost,
    _ => null,
  };

  final ReliabilityWindow window90d;
  final ReliabilityWindow window30d;
  final bool topRated;
  final bool negativeRating30d;
  final List<ReliabilityFailure> failures;

  /// Web's `describeReliability(...).completionPct`: null until there are
  /// enough orders for the share to mean anything.
  int? get completionPct => window90d.publicCompletionPct;

  int get cancelPct => window90d.paidOrders > 0
      ? (window90d.sellerCancels * 100 / window90d.paidOrders).round()
      : 0;

  /// Over the cancel limit, with enough orders for it to count.
  bool get belowStandard =>
      window90d.paidOrders >= minOrdersForPublicMetrics &&
      window90d.sellerCancels / window90d.paidOrders > sellerCancelLimit;

  int? get medianShipHours => window90d.medianShipHours?.ceil();

  /// Web's `topSellerRequirements`, over the last 30 days. Labels are the
  /// app design's shorter ones; what each checks is web's.
  List<TopSellerRequirement> get topSellerRequirements {
    final w = window30d;
    final cancelRate = w.paidOrders > 0 ? w.sellerCancels / w.paidOrders : 0.0;
    final ordersShort = _topSellerMinCompleted - w.completedOrders;
    final median = w.medianShipHours;
    return [
      TopSellerRequirement(
        label: 'Minimal $_topSellerMinCompleted pesanan selesai',
        met: ordersShort <= 0,
        detail: ordersShort > 0
            ? 'Kurang $ordersShort pesanan lagi'
            : '${w.completedOrders} pesanan selesai',
      ),
      TopSellerRequirement(
        label: 'Batal karena penjual maks. 5%',
        met: cancelRate <= _topSellerMaxCancelRate,
        detail: 'Rate batal ${(cancelRate * 100).round()}%',
      ),
      TopSellerRequirement(
        label: 'Median waktu kirim maks. $_topSellerMaxMedianHours jam',
        met: median != null && median <= _topSellerMaxMedianHours,
        detail: median == null
            ? 'Belum ada pesanan terkirim'
            : 'Median ${median.ceil()} jam',
      ),
      TopSellerRequirement(
        label: 'Tanpa komplain kalah & rating negatif',
        met: w.disputesLost == 0 && !negativeRating30d,
        detail: w.disputesLost > 0
            ? '${w.disputesLost} komplain kalah'
            : negativeRating30d
            ? 'Ada rating negatif'
            : 'Bersih',
      ),
    ];
  }

  static const minOrdersForPublicMetrics = 5;
  static const sellerCancelLimit = 0.1;
  static const _topSellerMinCompleted = 20;
  static const _topSellerMaxCancelRate = 0.05;
  static const _topSellerMaxMedianHours = 24;
}

class TopSellerRequirement {
  const TopSellerRequirement({
    required this.label,
    required this.met,
    required this.detail,
  });

  final String label;
  final bool met;
  final String detail;
}
