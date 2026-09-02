import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';

/// One courier the seller can name when typing in a resi — an entry of
/// `/api/biteship/couriers`.
class ManualCourier {
  const ManualCourier({required this.code, required this.name});

  factory ManualCourier.fromJson(Map<String, dynamic> json) => ManualCourier(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  final String code;
  final String name;
}

/// The shipment actions a seller takes on an order — web's
/// `SellerShipmentActions`, minus the parts that only make sense on a big
/// screen.
///
/// Everything here goes through pokepedia.id rather than Postgres: booking a
/// courier needs the Biteship key, and `/api/shipments/[shipmentSlug]/*`
/// already owns the state machine both clients depend on.
class ShipmentRepository {
  ShipmentRepository(this._api);

  final PokepediaApi _api;

  /// The couriers a manual resi may be filed under. Instant couriers are
  /// filtered out by the route itself — they cannot be dropped off.
  Future<List<ManualCourier>> fetchManualCouriers() async {
    final response = await _api.get('/api/biteship/couriers');
    final couriers = response['couriers'];
    if (couriers is! List) return const [];
    return couriers
        .whereType<Map<String, dynamic>>()
        .map(ManualCourier.fromJson)
        .where((c) => c.code.isNotEmpty)
        .toList();
  }

  /// Books the courier to come and collect. Returns null on success, or the
  /// message to show.
  Future<String?> dispatchPickup({
    required String shipmentSlug,
    required String itemName,
    String note = '',
  }) {
    return _dispatch(shipmentSlug, {
      'method': 'pickup',
      'sender_item_name': itemName,
      'sender_note': note,
    });
  }

  /// Files a resi the seller got at the counter themselves.
  Future<String?> dispatchManual({
    required String shipmentSlug,
    required String trackingNumber,
    required String courierCode,
  }) {
    return _dispatch(shipmentSlug, {
      'method': 'manual',
      'tracking_number': trackingNumber,
      'courier_code': courierCode,
    });
  }

  Future<String?> _dispatch(String slug, Map<String, dynamic> body) async {
    try {
      final response = await _api.post('/api/shipments/$slug/dispatch', body);
      // The route answers 200 with `ok: false` when the booking itself was
      // refused, so a successful HTTP call is not yet a successful dispatch.
      if (response['ok'] == false) {
        return response['error'] as String? ?? 'Gagal mengatur pengiriman';
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Terjadi kesalahan jaringan';
    }
  }
}

final shipmentRepositoryProvider = Provider(
  (ref) => ShipmentRepository(ref.read(pokepediaApiProvider)),
);

/// The courier list for the manual-resi form. Fetched once per app run — it
/// is Biteship's catalogue, not this order's.
final manualCouriersProvider = FutureProvider<List<ManualCourier>>(
  (ref) => ref.read(shipmentRepositoryProvider).fetchManualCouriers(),
);
