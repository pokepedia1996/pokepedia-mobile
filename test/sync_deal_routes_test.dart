import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/core/providers/device_fingerprint.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/trading_models.dart';
import 'package:pokepedia_mobile/features/expansions/repository/trading_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client() => SupabaseClient('http://localhost', 'anon-key');

const _fingerprint = '0123456789abcdef0123456789abcdef';

class _FixedFingerprint extends DeviceFingerprint {
  _FixedFingerprint() : super(_client());

  @override
  Future<String> value() async => _fingerprint;
}

class _ScriptedApi extends PokepediaApi {
  _ScriptedApi({this.error}) : super(_client());

  final ApiException? error;
  String? path;
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    this.path = path;
    this.body = body;
    if (error != null) throw error!;
    return const {'ok': true};
  }
}

TradingRepository _trading(_ScriptedApi api) =>
    TradingRepository(_client(), api: api, fingerprint: _FixedFingerprint());

void main() {
  group('shipping rates reason', () {
    test('parses each wire value and drops unknown ones', () {
      expect(
        CheckoutGateway.parseRateQuote({
          'services': [],
          'reason': 'no_coverage',
        }).reason,
        RatesReason.noCoverage,
      );
      expect(
        CheckoutGateway.parseRateQuote({
          'services': [],
          'reason': 'seller_restricted',
        }).reason,
        RatesReason.sellerRestricted,
      );
      expect(
        CheckoutGateway.parseRateQuote({
          'services': [
            {'courier': 'jne', 'service': 'reg', 'cost': 9000},
          ],
          'reason': 'seller_restricted_partial',
        }),
        isA<RateQuote>()
            .having((q) => q.services.single.cost, 'cost', 9000)
            .having(
              (q) => q.reason,
              'reason',
              RatesReason.sellerRestrictedPartial,
            ),
      );
      expect(
        CheckoutGateway.parseRateQuote({'reason': 'mystery'}).reason,
        isNull,
      );
    });

    test('empty-list copy matches EMPTY_COURIER_MESSAGES', () {
      expect(
        emptyCourierMessage(RatesReason.noCoverage),
        'Penjual ini tidak melayani pengiriman ke alamatmu',
      );
      expect(
        emptyCourierMessage(RatesReason.sellerRestricted),
        'Penjual ini tidak menerima kurir yang melayani rute ke alamatmu',
      );
      expect(emptyCourierMessage(null), 'Layanan kurir sedang gangguan');
    });
  });

  group('POST /api/cart', () {
    test('body carries the slug and the device fingerprint', () {
      expect(
        CartRepository.addToCartBody(
          askOrderSlug: 'slug-1',
          quantity: 2,
          deviceFingerprint: _fingerprint,
        ),
        {
          'askOrderSlug': 'slug-1',
          'quantity': 2,
          'deviceFingerprint': _fingerprint,
        },
      );
    });

    test('a coded refusal keeps the code and the route\'s sentence', () {
      final e = cartExceptionFromApi(
        const ApiException(
          'Hanya 1 tersedia',
          statusCode: 400,
          code: 'insufficient_quantity',
        ),
      );
      expect(e.code, 'insufficient_quantity');
      expect(e.message, 'Hanya 1 tersedia');
    });

    test('the slug lookup miss reads as order_not_found', () {
      final e = cartExceptionFromApi(
        const ApiException('Listing tidak ditemukan', statusCode: 404),
      );
      expect(e.code, 'order_not_found');
      expect(e.message, 'Listing tidak ditemukan');
    });

    test('a lost session reads as unauthorized', () {
      final e = cartExceptionFromApi(const ApiSessionExpiredException());
      expect(e.code, 'unauthorized');
      expect(e.message, 'Sesi habis, login ulang');
    });

    test('CartException is an ApiException with its own copy', () {
      const e = CartException('same_device_self_trade');
      expect(e, isA<ApiException>());
      expect(
        e.message,
        'Tidak dapat membeli listing dari akun lain di perangkat yang sama.',
      );
    });
  });

  group('POST /api/listings', () {
    test('posts PlaceOrderBodySchema with the fingerprint', () async {
      final api = _ScriptedApi();
      final result = await _trading(api).placeOrder(
        cardId: 42,
        side: 'ask',
        price: 150000,
        condition: CardCondition.psa10,
        quantity: 1,
        replace: true,
        photoUrls: const ['https://x.supabase.co/storage/v1/object/public/a'],
      );

      expect(result.isOk, isTrue);
      expect(api.path, '/api/listings');
      expect(api.body, {
        'cardId': 42,
        'variantKey': null,
        'side': 'ask',
        'price': 150000,
        'condition': 'PSA10',
        'quantity': 1,
        'replaceExisting': true,
        'autoRelist': false,
        'acceptsOffers': false,
        'photoUrls': ['https://x.supabase.co/storage/v1/object/public/a'],
        'deviceFingerprint': _fingerprint,
      });
    });

    test('a bid sends no photos', () async {
      final api = _ScriptedApi();
      await _trading(api).placeOrder(
        cardId: 42,
        side: 'bid',
        price: 150000,
        condition: CardCondition.nm,
        quantity: 1,
        photoUrls: const ['https://x/a.jpg'],
      );
      expect(api.body!['photoUrls'], isEmpty);
    });

    test('409 duplicate carries the existing price', () async {
      final result =
          await _trading(
            _ScriptedApi(
              error: const ApiException(
                ApiException.genericMessage,
                statusCode: 409,
                code: 'duplicate',
                payload: {'error': 'duplicate', 'existingPrice': 120000},
              ),
            ),
          ).placeOrder(
            cardId: 1,
            side: 'bid',
            price: 1,
            condition: CardCondition.nm,
            quantity: 1,
          );
      expect(result.status, PlaceOrderStatus.duplicate);
      expect(result.existingPrice, 120000);
    });

    test('listing_reserved_by_deal keeps its side-specific copy', () async {
      final result =
          await _trading(
            _ScriptedApi(
              error: const ApiException(
                'Bid ini sedang dipakai di checkout yang belum selesai.',
                statusCode: 409,
                code: 'listing_reserved_by_deal',
              ),
            ),
          ).placeOrder(
            cardId: 1,
            side: 'bid',
            price: 1,
            condition: CardCondition.nm,
            quantity: 1,
          );
      expect(result.code, 'listing_reserved_by_deal');
      expect(
        result.messageId,
        startsWith('Bid ini sedang dipakai di checkout'),
      );
    });

    test('code-less refusals are recognised by their sentence', () {
      expect(
        TradingRepository.placeOrderResultFromApi(
          const ApiException(
            'Foto wajib untuk kartu graded (slab).',
            statusCode: 400,
          ),
          side: 'ask',
        ).code,
        'photo_required',
      );
      expect(
        TradingRepository.placeOrderResultFromApi(
          const ApiException('Jumlah tidak valid', statusCode: 400),
          side: 'ask',
        ).code,
        'invalid_quantity',
      );
      expect(
        TradingRepository.placeOrderResultFromApi(
          const ApiException(
            'Verifikasi nomor HP terlebih dahulu',
            statusCode: 403,
          ),
          side: 'bid',
        ).code,
        'phone_not_verified',
      );
      expect(
        TradingRepository.placeOrderResultFromApi(
          const ApiException('Gagal memasang order', statusCode: 500),
          side: 'bid',
        ).code,
        'unknown',
      );
    });
  });
}
