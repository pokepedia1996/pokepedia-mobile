import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notification_route.dart';

/// `action_url` is written by Postgres triggers for the website. Every value
/// below is one the migrations actually emit, so a mapping that drifts sends
/// a tapped notification to the router's error page — the failure is silent
/// until somebody taps one.
void main() {
  group('buyer paths', () {
    test('an order opens that order', () {
      expect(appRouteForActionUrl('/orders/abc-123'), '/orders/abc-123');
      expect(appRouteForActionUrl('/orders'), '/orders');
    });

    test('chat opens the thread when the row names one', () {
      expect(appRouteForActionUrl('/chat'), '/chat');
      expect(appRouteForActionUrl('/chat/room-9'), '/chat/room-9');
    });

    test('a storefront opens by its handle', () {
      expect(appRouteForActionUrl('/market/toko-abc'), '/market/toko-abc');
      expect(appRouteForActionUrl('/market'), '/market');
    });

    test("web's proposal tabs become the app's filters", () {
      // The two are not the same axis: web splits by direction, the app by
      // what a proposal is waiting on.
      expect(
        appRouteForActionUrl('/proposals?tab=diterima'),
        '/proposals?filter=perlu_aksi',
      );
      expect(
        appRouteForActionUrl('/proposals?tab=dikirim'),
        '/proposals?filter=menunggu',
      );
      expect(appRouteForActionUrl('/proposals'), '/proposals');
    });
  });

  group('seller paths', () {
    test('a seller order opens that order, not the buyer copy', () {
      expect(
        appRouteForActionUrl('/seller/orders/ord-1'),
        '/seller/orders/ord-1',
      );
    });

    test('a filtered seller list keeps a filter the app knows', () {
      expect(
        appRouteForActionUrl('/seller/orders?filter=urgent'),
        '/seller/orders?filter=urgent',
      );
      expect(
        appRouteForActionUrl('/seller/orders?filter=nonsense'),
        '/seller/orders',
      );
    });

    test('a dispute lands on the disputed orders it can be worked from', () {
      // The app has no seller dispute screen; dropping the tap would leave
      // the loudest notification there is doing nothing.
      expect(
        appRouteForActionUrl('/seller/disputes/dsp-1'),
        '/seller/orders?filter=disputed',
      );
    });

    test('the offers bucket falls back to the listings list', () {
      expect(
        appRouteForActionUrl('/seller/products?filter=penawaran'),
        '/seller/products',
      );
    });

    test('seller proposals open the ones waiting on an answer', () {
      expect(
        appRouteForActionUrl('/seller/proposals'),
        '/proposals?filter=perlu_aksi',
      );
    });
  });

  group('anything else', () {
    test('is not navigated to', () {
      // A path with no screen here would land on the router's error page.
      expect(appRouteForActionUrl('/admin/queue'), isNull);
      expect(appRouteForActionUrl('/seller/analytics'), isNull);
      expect(appRouteForActionUrl('https://pokepedia.id/orders/1'), isNull);
      expect(appRouteForActionUrl(''), isNull);
      expect(appRouteForActionUrl(null), isNull);
    });
  });
}
