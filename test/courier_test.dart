import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/shared/utils/courier.dart';

void main() {
  group('courierDisplayName', () {
    test('names couriers the way the site does', () {
      // The seller page carried its own drifted copy of this table — "J&T"
      // against the site's "J&T Express", "POS Indonesia" against "Pos
      // Indonesia". One courier under two names reads as two couriers.
      expect(courierDisplayName('jnt'), 'J&T Express');
      expect(courierDisplayName('pos'), 'Pos Indonesia');
      expect(courierDisplayName('sicepat'), 'SiCepat');
      expect(courierDisplayName('anteraja'), 'AnterAja');
    });

    test('an unmapped courier still prints, upper-cased', () {
      expect(courierDisplayName('wahana'), 'WAHANA');
    });

    test('nothing to show for nothing', () {
      expect(courierDisplayName(null), isNull);
      expect(courierDisplayName('  '), isNull);
    });
  });

  group('getTrackingUrl', () {
    test('SAP takes the resi straight into the URL', () {
      final r = getTrackingUrl('sap', 'SAP123456');
      expect(r.mode, TrackingMode.direct);
      expect(r.url, 'https://www.sapx.id/id/cek-awb/SAP123456');
    });

    test('a direct courier with no resi falls back to the universal tracker', () {
      expect(getTrackingUrl('sap', null).mode, TrackingMode.manual);
      expect(getTrackingUrl('sap', '  ').url, 'https://cekresi.com/');
    });

    test('couriers with only a form get their landing page', () {
      final r = getTrackingUrl('jne', 'JNE0001');
      expect(r.mode, TrackingMode.manual);
      expect(r.url, 'https://www.jne.co.id/tracking-package');
    });

    test('Biteship\'s "id" is ID Express', () {
      // `normalizeCourierCode`: the alias has to resolve or the lookup misses.
      expect(normalizeCourierCode('id'), 'idexpress');
      expect(getTrackingUrl('id', 'X1').url, 'https://idexpress.com/lacak-paket');
    });

    test('an unknown courier lands on cekresi rather than nowhere', () {
      expect(getTrackingUrl('wahana', 'X1').url, 'https://cekresi.com/');
      expect(getTrackingUrl(null, 'X1').url, 'https://cekresi.com/');
    });
  });

  group('sellerHandle', () {
    Map<String, dynamic> row() => {
      'id': 1,
      'slug': 'o1',
      'order_number': 'ORD-1',
      'status': 'awaiting_shipment',
      'created_at': '2026-08-19T09:00:00+00:00',
      'order_items': <Map<String, dynamic>>[],
    };

    test('the store slug wins when there is one', () {
      final order = OrderModel.fromRow(
        row(),
        storeName: 'Toko',
      ).withSeller(slug: 'toko-ash', username: 'ash');
      expect(order.sellerHandle, 'toko-ash');
    });

    test('a seller with no storefront still opens on their username', () {
      // Web's `resolveSellerDisplay` falls back this way; mobile drew a
      // chevron that went nowhere.
      final order = OrderModel.fromRow(
        row(),
        storeName: 'Toko',
      ).withSeller(slug: null, username: 'ash');
      expect(order.sellerHandle, 'ash');
    });

    test('an unsafe username is not turned into a route', () {
      final order = OrderModel.fromRow(
        row(),
        storeName: 'Toko',
      ).withSeller(slug: null, username: 'ash/../admin');
      expect(order.sellerHandle, isNull);
    });
  });
}
