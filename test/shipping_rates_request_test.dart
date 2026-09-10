import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records what the gateway sends instead of sending it. The client is a
/// throwaway: nothing in these paths touches Postgres.
class _RecordingApi extends PokepediaApi {
  _RecordingApi(this.response)
    : super(SupabaseClient('http://localhost', 'anon-key'));

  final Map<String, dynamic> response;
  String? path;
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    this.path = path;
    this.body = body;
    return response;
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    this.path = path;
    return response;
  }
}

/// Courier quotes moved off the `shipping-rates` Edge Function onto the same
/// `/api/shipping/rates` route the web checkout calls. The route prices from
/// the body alone, so a field dropped here is a wrong price, not an error.
void main() {
  group('fetchRates', () {
    test('posts to the web route with web\'s own parameter names', () async {
      final api = _RecordingApi({'services': []});
      await CheckoutGateway(
        api,
        SupabaseClient('http://localhost', 'anon-key'),
      ).fetchRates(
        originCityId: '31.71',
        destinationCityId: '32.73',
        quantity: 3,
        itemValue: 250000,
        originLat: -6.2,
        originLng: 106.8,
        destinationLat: -6.9,
        destinationLng: 107.6,
        acceptedCouriers: ['jne'],
        acceptedCourierServices: ['jne/reg'],
      );

      expect(api.path, '/api/shipping/rates');
      expect(api.body!['originCityId'], '31.71');
      expect(api.body!['destinationCityId'], '32.73');
      // SHIPPING_WEIGHT_PER_UNIT_GRAMS × quantity.
      expect(api.body!['weight'], 30);
      expect(api.body!['itemValue'], 250000);
      expect(api.body!['includeInsurance'], isTrue);
      expect(api.body!['originLat'], -6.2);
      expect(api.body!['destinationLng'], 107.6);
      expect(api.body!['acceptedCourierServices'], ['jne/reg']);
    });

    test('quotes at least one unit of weight', () async {
      final api = _RecordingApi({'services': []});
      await CheckoutGateway(
        api,
        SupabaseClient('http://localhost', 'anon-key'),
      ).fetchRates(
        originCityId: '31.71',
        destinationCityId: '32.73',
        quantity: 0,
        itemValue: 0,
      );

      expect(api.body!['weight'], kShippingWeightPerUnitGrams);
      // Nothing to insure, and quoting the premium would also bypass the
      // route's rate cache.
      expect(api.body!['includeInsurance'], isFalse);
      expect(api.body!.containsKey('itemValue'), isFalse);
      expect(api.body!.containsKey('originLat'), isFalse);
    });

    test('parses the services envelope the route returns', () async {
      final api = _RecordingApi({
        'services': [
          {
            'courier': 'jne',
            'courierName': 'JNE',
            'service': 'REG',
            'description': 'Layanan Reguler',
            'cost': 12000,
            'durationRange': '2-3',
            'durationUnit': 'days',
            'insuranceAvailable': true,
            'insuranceFee': 2500,
          },
        ],
      });
      final options =
          await CheckoutGateway(
            api,
            SupabaseClient('http://localhost', 'anon-key'),
          ).fetchRates(
            originCityId: '31.71',
            destinationCityId: '32.73',
            quantity: 1,
            itemValue: 100000,
          );

      expect(options, hasLength(1));
      expect(options.first.courier, 'jne');
      expect(options.first.cost, 12000);
      expect(options.first.insuranceFee, 2500);
    });
  });

  group('fetchSellerOrigins', () {
    test('reads the origins GET /api/cart resolves server-side', () async {
      final api = _RecordingApi({
        'sellerOrigins': {
          'seller-1': {
            'cityId': '31.71',
            'cityName': 'Jakarta Selatan',
            'pickupLat': -6.2,
            'pickupLng': 106.8,
            'acceptedCouriers': ['jne', 'sicepat'],
            'acceptedCourierServices': ['jne/reg'],
            'isActive': true,
          },
        },
      });
      final origins = await CheckoutGateway(
        api,
        SupabaseClient('http://localhost', 'anon-key'),
      ).fetchSellerOrigins();

      expect(api.path, '/api/cart');
      expect(origins['seller-1']!.cityId, '31.71');
      expect(origins['seller-1']!.acceptedCouriers, ['jne', 'sicepat']);
      expect(origins['seller-1']!.isActive, isTrue);
    });

    test('is empty when the cart names no sellers', () async {
      final api = _RecordingApi({'sellerOrigins': {}});
      final origins = await CheckoutGateway(
        api,
        SupabaseClient('http://localhost', 'anon-key'),
      ).fetchSellerOrigins();
      expect(origins, isEmpty);
    });
  });
}
