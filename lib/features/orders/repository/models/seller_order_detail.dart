import '../../../../shared/utils/postgrest_embed.dart';
import 'order_model.dart';

/// Where the parcel is going. Only populated once a shipment row exists —
/// before that the buyer's address is still theirs alone.
class ShipmentDestination {
  const ShipmentDestination({
    this.contactName,
    this.contactPhone,
    this.fullAddress,
    this.district,
    this.city,
    this.province,
    this.postalCode,
  });

  factory ShipmentDestination.fromRow(Map<String, dynamic> row) {
    return ShipmentDestination(
      contactName: row['destination_contact_name'] as String?,
      contactPhone: row['destination_contact_phone'] as String?,
      fullAddress: row['destination_full_address'] as String?,
      district: row['destination_district'] as String?,
      city: row['destination_city'] as String?,
      province: row['destination_province'] as String?,
      postalCode: row['destination_postal_code'] as String?,
    );
  }

  final String? contactName;
  final String? contactPhone;
  final String? fullAddress;
  final String? district;
  final String? city;
  final String? province;
  final String? postalCode;

  /// District · city · province · postcode, skipping whatever is missing.
  String get areaLine => [
    district,
    city,
    province,
    postalCode,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  bool get isEmpty =>
      (contactName ?? '').isEmpty &&
      (fullAddress ?? '').isEmpty &&
      areaLine.isEmpty;
}

/// One order as its *seller* sees it: web's `/seller/orders/[matchId]`.
///
/// Distinct from the buyer's view of the same row. A buyer wants what they
/// paid and where the parcel is; a seller wants who bought it, what to send,
/// and what lands in their balance after commission — which is why the money
/// here is the settlement's, not the invoice's.
class SellerOrderDetail {
  const SellerOrderDetail({
    required this.order,
    required this.subtotal,
    required this.shippingCost,
    required this.insuranceFee,
    required this.commissionAmount,
    required this.sellerNetAmount,
    this.buyerUsername,
    this.destination,
  });

  /// Builds the seller view from one `orders` row.
  ///
  /// Web reaches sideways here — it starts from a single match and pulls in
  /// the checkout's other matches to aggregate. The app's `orders` row is
  /// already that grouping (one row, many `order_items`), so the sum is over
  /// this order's own items.
  factory SellerOrderDetail.fromRow(
    Map<String, dynamic> row, {
    required OrderModel order,
    String? buyerUsername,
  }) {
    var subtotal = 0;
    var shipping = 0;
    var insurance = 0;
    var commission = 0;
    var net = 0;

    for (final entry in (row['order_items'] as List?) ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      final settlement = embeddedRow(entry['settlements']);
      subtotal +=
          ((entry['match_price'] as num?)?.toInt() ?? 0) *
          ((entry['matched_quantity'] as num?)?.toInt() ?? 0);
      if (settlement == null) continue;
      shipping += (settlement['shipping_cost'] as num?)?.toInt() ?? 0;
      insurance += (settlement['insurance_premium_idr'] as num?)?.toInt() ?? 0;
      commission += (settlement['commission_amount'] as num?)?.toInt() ?? 0;
      net += (settlement['seller_net_amount'] as num?)?.toInt() ?? 0;
    }

    final shipment = embeddedRow(row['shipments']);
    final destination = shipment == null
        ? null
        : ShipmentDestination.fromRow(shipment);

    return SellerOrderDetail(
      order: order,
      buyerUsername: buyerUsername,
      destination: destination != null && !destination.isEmpty
          ? destination
          : null,
      subtotal: subtotal,
      shippingCost: shipping,
      insuranceFee: insurance,
      commissionAmount: commission,
      sellerNetAmount: net,
    );
  }

  final OrderModel order;
  final String? buyerUsername;
  final ShipmentDestination? destination;

  /// What the cards themselves came to, before shipping.
  final int subtotal;
  final int shippingCost;
  final int insuranceFee;

  /// The platform's cut, already deducted from [sellerNetAmount].
  final int commissionAmount;

  /// What actually reaches the seller's balance when escrow releases.
  final int sellerNetAmount;

  /// What the buyer was charged for this seller's part of the checkout.
  ///
  /// Deliberately excludes the gateway fee and any coupon: those live on
  /// `carts`, which `carts_select_own` reserves for the buyer. Web's page
  /// reads them with the seller's own session too, so it shows the same
  /// figure — naming this "what the buyer paid you" rather than "what the
  /// buyer paid" is the honest version.
  int get buyerPaid => subtotal + shippingCost + insuranceFee;

  /// Whether the money is still the platform's to hold.
  bool get inEscrow => order.items.any(
    (item) => item.settlementStatus == 'in_escrow' && item.dispute == null,
  );

  bool get hasOpenDispute => order.items.any((item) => item.dispute != null);

  int get disputedCount =>
      order.items.where((item) => item.dispute != null).length;

  /// The buyer has paid but nothing has been handed to a courier yet — the
  /// state the seller is expected to act on.
  bool get awaitingShipment =>
      order.shipmentStatus == 'awaiting_shipment' ||
      (order.shipmentStatus == null &&
          order.items.any((i) => i.paidAt != null));

  bool get awaitingPayment => order.items.every((item) => item.paidAt == null);
}
