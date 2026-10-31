import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_order_detail_page.dart';
import 'package:pokepedia_mobile/shared/widgets/inline_pill.dart';

/// The seller order page's shipping chip reads every `shipments.status` in
/// Indonesian, as web's seller order list does — never the raw value.
OrderModel _order(String? shipmentStatus) => OrderModel(
  slug: 'o',
  orderNumber: 'ord-1',
  storeName: 'Toko',
  status: OrderStatus.shipped,
  createdAt: DateTime(2026, 10, 1),
  items: const [],
  shipmentStatus: shipmentStatus,
);

void main() {
  test('the app\'s own statuses get web\'s labels and tones', () {
    final cases = {
      'awaiting_shipment': ('Menunggu dikirim', InlinePillTone.warning),
      'awaiting_pickup': ('Menunggu pickup', InlinePillTone.progress),
      'shipped': ('Dikirim', InlinePillTone.shipped),
      'received': ('Tiba di tujuan', InlinePillTone.success),
      'completed': ('Selesai', InlinePillTone.success),
      'cancelled': ('Pengiriman dibatalkan', InlinePillTone.neutral),
      'issue': ('Bermasalah', InlinePillTone.danger),
    };
    for (final MapEntry(key: status, value: (label, tone)) in cases.entries) {
      final pill = sellerShipmentPill(_order(status));
      expect(pill.label, label, reason: status);
      expect(pill.tone, tone, reason: status);
    }
  });

  test('older Biteship words and the unknown still read in Indonesian', () {
    expect(sellerShipmentPill(_order('delivered')).label, 'Tiba di tujuan');
    expect(sellerShipmentPill(_order('picked')).label, 'Dikirim');
    expect(sellerShipmentPill(_order(null)).label, 'Menunggu dikirim');
    expect(
      sellerShipmentPill(_order('something_new')).label,
      'Status tidak diketahui',
    );
  });
}
