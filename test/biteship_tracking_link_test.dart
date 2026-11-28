import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';

/// The parcel's own Biteship page (`shipments.courier_link`) backs the
/// external-link button on "Lacak paket", as on web: https only, and kept
/// when the order is copied with its seller.
void main() {
  OrderModel order(String? link) => OrderModel.fromRow({
    'id': 1,
    'slug': 'o1',
    'order_number': 'ORD-1',
    'status': 'shipped',
    'created_at': '2026-08-19T09:00:00+00:00',
    'order_items': <Map<String, dynamic>>[],
    'shipments': [
      {'tracking_number': 'C1YQORLO', 'courier': 'lion', 'courier_link': link},
    ],
  }, storeName: 'Toko');

  test('reads the parcel page Biteship gave', () {
    final o = order('https://track.biteship.com/abc123');
    expect(o.courierLink, 'https://track.biteship.com/abc123');
    expect(o.biteshipTrackingUrl, 'https://track.biteship.com/abc123');
  });

  test('offers no button without a link, or for one that is not https', () {
    expect(order(null).biteshipTrackingUrl, isNull);
    expect(order('http://track.biteship.com/abc').biteshipTrackingUrl, isNull);
    expect(order('javascript:alert(1)').biteshipTrackingUrl, isNull);
  });

  test('survives the copy that adds the seller', () {
    final o = order(
      'https://track.biteship.com/abc123',
    ).withSeller(slug: 'toko', username: 'ash');
    expect(o.biteshipTrackingUrl, 'https://track.biteship.com/abc123');
  });
}
