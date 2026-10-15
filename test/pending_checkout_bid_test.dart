import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/pending_checkout.dart';

Map<String, dynamic> _row({String kind = 'bid', String? invoiceUrl}) => {
  'id': 9,
  'external_id': 'INV-BID-9',
  'kind': kind,
  'status': 'pending',
  'total_amount': 30000,
  'created_at': '2026-10-15T05:00:00Z',
  'expires_at': '2026-10-16T05:00:00Z',
  'invoice_url': invoiceUrl,
  'cart_snapshot': [
    {
      'card_id': 812,
      'card_name': 'Poffin Bersahabat',
      'card_image': 'https://images.pokepedia.id/cards/812.png',
      'price': 30000,
      'quantity': 1,
      'seller_id': 's1',
      'bid_order_id': 44,
    },
  ],
};

void main() {
  test('an accepted bid with no invoice yet is a cart deal, not an order', () {
    // Web's isPreInvoiceDeal: it waits in Keranjang until checkout.
    expect(isPreInvoiceDeal(_row()), isTrue);
    expect(isPreInvoiceDeal(_row(invoiceUrl: 'https://x.id/inv')), isFalse);
    expect(isPreInvoiceDeal(_row(kind: 'cart')), isFalse);
  });

  test('a bid line takes its art from card_image', () {
    // accept_bid_proposal writes `card_image`, not `card_image_url`; reading
    // only the latter left the placeholder icon on the order card.
    final checkout = pendingCheckoutFromCart(
      _row(invoiceUrl: 'https://x.id/inv'),
    );
    expect(
      checkout.items.single.imageUrl,
      'https://images.pokepedia.id/cards/812.png',
    );
  });
}
