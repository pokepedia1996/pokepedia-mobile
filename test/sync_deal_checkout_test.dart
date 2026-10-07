import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_deal.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/features/cart/usecase/checkout_notifier.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/wallet_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client() => SupabaseClient('http://localhost', 'anon-key');

class _RecordingApi extends PokepediaApi {
  _RecordingApi(this.response) : super(_client());

  final Map<String, dynamic> response;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add((path, body));
    return response;
  }
}

const _dealId = 'INV-BID-261007-abc123def456';
const _dealSeller = '11111111-1111-1111-1111-111111111111';

final _deal = CheckoutDeal.fromCartRow({
  'external_id': _dealId,
  'expires_at': '2026-10-08T10:00:00Z',
  'cart_snapshot': [
    {
      'bid_order_id': 9,
      'seller_id': _dealSeller,
      'card_id': 42,
      'card_name': 'Lugia V',
      'card_image': 'https://cdn.example/lugia.png',
      'price': 300000,
      'quantity': 2,
      'condition': 'LP',
      'proposal_id': 7,
    },
  ],
})!;

class _DealGateway implements CheckoutGateway {
  final quotes = <int>[];
  final submitted = <List<String>>[];

  @override
  Future<CheckoutContext> fetchContext() async =>
      const CheckoutContext(phoneVerified: true);

  @override
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async => const {
    _dealSeller: SellerOrigin(cityId: '31.71', isActive: true),
  };

  @override
  Future<List<CheckoutDeal>> fetchDeals({List<String>? externalIds}) async => [
    _deal,
  ];

  @override
  Future<PaymentChannel?> fetchLastPaidChannel() async => null;

  @override
  Future<RateQuote> fetchRateQuote({
    required String originCityId,
    required String destinationCityId,
    required int quantity,
    required int itemValue,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
    List<String> acceptedCouriers = const [],
    List<String> acceptedCourierServices = const [],
  }) async {
    quotes.add(itemValue);
    return const RateQuote(
      services: [
        CourierOption(
          courier: 'jne',
          courierName: 'JNE',
          service: 'reg',
          description: 'Reguler',
          cost: 12000,
          durationRange: '2-3',
          durationUnit: 'days',
          insuranceAvailable: true,
          insuranceFee: 3000,
        ),
      ],
      reason: RatesReason.sellerRestrictedPartial,
    );
  }

  @override
  Future<List<AvailableCoupon>> fetchAvailableCoupons({
    required int shippingTotal,
    required PaymentChannel? paymentChannel,
    required List<int> selectedCartItemIds,
    List<String> dealExternalIds = const [],
  }) async => const [];

  @override
  Future<CheckoutResult> submitDeals({
    required List<String> dealExternalIds,
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    List<int> couponIds = const [],
  }) async {
    submitted.add(dealExternalIds);
    return const CheckoutResult(invoiceUrl: 'https://checkout.xendit.co/x');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

const _address = AddressModel(
  id: 1,
  slug: '22222222-2222-2222-2222-222222222222',
  label: 'Rumah',
  contactName: 'Buyer',
  contactPhone: '0800',
  provinceId: '9',
  provinceName: 'Jawa Barat',
  cityId: '32.73',
  cityName: 'Bandung',
  districtId: '4567',
  district: 'Coblong',
  fullAddress: 'Jl. Test 1',
  isPrimary: true,
);

void main() {
  group('deal-only checkout request', () {
    test(
      'sends selectedCartItemIds as [] so the cart is not pulled in',
      () async {
        final api = _RecordingApi({
          'invoiceUrl': 'https://x',
          'externalId': 'INV-1',
        });
        await CheckoutGateway(api, _client()).submitDeals(
          dealExternalIds: const [_dealId],
          courierChoices: const [
            CourierChoice(
              sellerId: _dealSeller,
              courier: 'jne',
              service: 'reg',
              insuranceEnabled: true,
            ),
          ],
          deliveryAddressSlug: _address.slug,
          paymentMethod: PaymentMethod.xendit,
          paymentChannel: PaymentChannel.bni,
        );

        final (path, body) = api.calls.single;
        expect(path, '/api/cart/checkout');
        expect(body.containsKey('selectedCartItemIds'), isTrue);
        expect(body['selectedCartItemIds'], isEmpty);
        expect(body['selectedDealExternalIds'], [_dealId]);
        expect(body['paymentChannel'], 'BNI');
      },
    );

    test('a cart checkout with no selection still omits the field', () {
      final body = CheckoutGateway.checkoutRequestBody(
        courierChoices: const [],
        deliveryAddressSlug: _address.slug,
        paymentMethod: PaymentMethod.wallet,
      );
      expect(body.containsKey('selectedCartItemIds'), isFalse);
      expect(body.containsKey('selectedDealExternalIds'), isFalse);
      expect(body['paymentMethod'], 'wallet');
    });

    test('coupons are priced with the deals named', () async {
      final api = _RecordingApi({'coupons': []});
      await CheckoutGateway(api, _client()).fetchAvailableCoupons(
        shippingTotal: 12000,
        paymentChannel: null,
        selectedCartItemIds: const [],
        dealExternalIds: const [_dealId],
      );
      final (path, body) = api.calls.single;
      expect(path, '/api/coupons/available');
      expect(body['selectedCartItemIds'], isEmpty);
      expect(body['dealExternalIds'], [_dealId]);
    });
  });

  group('CheckoutDeal', () {
    test('reads accept_bid_proposal\'s snapshot', () {
      expect(_deal.externalId, _dealId);
      expect(_deal.sellerId, _dealSeller);
      expect(_deal.subtotal, 600000);
      expect(_deal.quantity, 2);
      final line = _deal.lines.single;
      expect(line.cardId, 42);
      expect(line.imageUrl, 'https://cdn.example/lugia.png');
      expect(line.condition, CardCondition.lp);
    });

    test('a snapshot with no seller is not payable', () {
      expect(
        CheckoutDeal.fromCartRow({
          'external_id': _dealId,
          'cart_snapshot': [
            {'price': 1, 'quantity': 1},
          ],
        }),
        isNull,
      );
    });
  });

  group('CheckoutNotifier in a deal checkout', () {
    late _DealGateway gateway;
    late ProviderContainer container;

    setUp(() {
      gateway = _DealGateway();
      container = ProviderContainer(
        overrides: [
          checkoutGatewayProvider.overrideWithValue(gateway),
          checkoutDealIdsProvider.overrideWithValue(const [_dealId]),
          selectedCartItemsProvider.overrideWithValue(const []),
          walletBalanceProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);
    });

    test('prices, quotes and submits the deal alone', () async {
      final visit = container.listen(checkoutProvider, (_, __) {});
      addTearDown(visit.close);
      final notifier = container.read(checkoutProvider.notifier);

      await notifier.loadContext();
      expect(notifier.isDealCheckout, isTrue);
      expect(notifier.sellerIds, [_dealSeller]);
      expect(notifier.itemsSubtotal, 600000);
      // Over Rp500.000 counting the deal, as the route's sellerTotalValue does.
      expect(notifier.isInsuranceMandatoryFor(_dealSeller), isTrue);

      notifier.selectAddress(_address);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await pumpEventQueue();

      expect(gateway.quotes, [600000]);
      final shipping = container.read(checkoutProvider).shippingBySeller;
      expect(shipping[_dealSeller]?.selected?.courier, 'jne');
      expect(
        shipping[_dealSeller]?.reason,
        RatesReason.sellerRestrictedPartial,
      );

      notifier.selectXendit(PaymentChannel.bni);
      expect(notifier.blockedReason, isNull);

      final result = await notifier.submit();
      expect(result.invoiceUrl, isNotNull);
      expect(gateway.submitted, [
        [_dealId],
      ]);
    });
  });
}
