import '../../../../shared/utils/postgrest_embed.dart';
import 'order_model.dart';
import 'shipment_destination.dart';

// Re-exported: this file used to define `ShipmentDestination`, and the
// seller detail page still imports it from here.
export 'shipment_destination.dart';

/// `INSTANT_COURIER_COMPANY_CODES` in `lib/shipping/core/instant-couriers.ts`
/// — the on-demand couriers, which only ever pick up.
const _instantCourierCompanies = {'grab', 'gojek'};

/// Reads `available_collection_method`, which Postgres hands back either as
/// an array or as one comma-joined string depending on the column type.
List<String>? _collectionMethods(Object? raw) {
  if (raw is List) {
    return raw.whereType<String>().map((s) => s.trim().toLowerCase()).toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return null;
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
    this.availableCollectionMethods,
    this.courierCompany,
    this.courierService,
    this.etdText,
    this.etdUnit,
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
    List<String>? collectionMethods;
    String? courierCompany;
    String? courierService;
    String? etdText;
    String? etdUnit;

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
      // One courier carries the whole order, so the first settlement that
      // names one speaks for all of them.
      collectionMethods ??= _collectionMethods(
        settlement['available_collection_method'],
      );
      courierCompany ??= settlement['courier_company'] as String?;
      courierService ??=
          settlement['courier_service'] as String? ??
          settlement['courier_service_code'] as String?;
      etdText ??= settlement['estimated_delivery_text'] as String?;
      etdUnit ??= settlement['estimated_delivery_unit'] as String?;
    }

    final shipment = embeddedRow(row['shipments']);
    final destination = shipment == null
        ? null
        : ShipmentDestination.fromRow(shipment);

    return SellerOrderDetail(
      order: order,
      buyerUsername: buyerUsername,
      availableCollectionMethods: collectionMethods,
      courierCompany: courierCompany,
      courierService: courierService,
      etdText: etdText,
      etdUnit: etdUnit,
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

  /// `settlements.available_collection_method` — what the booked courier
  /// will accept. Null means the courier never said, which web reads as
  /// "probably both, let the server decide".
  final List<String>? availableCollectionMethods;

  /// `settlements.courier_company`, the code the courier is booked under.
  final String? courierCompany;

  /// The service level the buyer paid for — "Reguler", "Instant", and so on.
  final String? courierService;

  /// `estimated_delivery_text` / `_unit`, the courier's own ETA.
  final String? etdText;
  final String? etdUnit;

  /// "1 - 2 hari" — web's `translateEtdUnit`, which turns the courier's
  /// English unit into the one the rest of the app speaks.
  String? get etd {
    final text = etdText?.trim();
    if (text == null || text.isEmpty) return null;
    final unit = switch (etdUnit?.toLowerCase()) {
      'day' || 'days' => 'hari',
      'hour' || 'hours' => 'jam',
      'minute' || 'minutes' => 'menit',
      final other => other ?? '',
    };
    return unit.isEmpty ? text : '$text $unit';
  }

  /// How the buyer's courier reads on screen: name, then service level.
  String? get buyerCourierLabel {
    final company = courierCompany?.trim();
    if (company == null || company.isEmpty) return null;
    final service = courierService?.trim();
    return service == null || service.isEmpty
        ? company.toUpperCase()
        : '${company.toUpperCase()} · $service';
  }

  /// Instant couriers ride along with a driver and cannot take a resi the
  /// seller typed in — web's `isInstantCourierCompany`.
  bool get isInstantCourier =>
      _instantCourierCompanies.contains((courierCompany ?? '').toLowerCase());

  /// Whether the seller may hand the parcel to a courier who comes to them.
  bool get allowsPickup =>
      availableCollectionMethods == null ||
      availableCollectionMethods!.contains('pickup');

  /// Whether the seller may drop the parcel off and type the resi in.
  bool get allowsManualResi => !isInstantCourier;

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
