import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/account/usecase/address_notifier.dart';
import 'package:pokepedia_mobile/features/cart/presentation/cart_page.dart';
import 'package:pokepedia_mobile/features/cart/presentation/checkout/seller_group_card.dart';
import 'package:pokepedia_mobile/features/cart/presentation/checkout_page.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_deal.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_deals.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_notifier.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/features/cart/usecase/checkout_notifier.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/card_proposals_page.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/proposals_repository.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/wallet_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/widgets/condition_badge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client() => SupabaseClient('http://localhost', 'anon-key');

const _dealId = 'INV-BID-261007-abc123def456';
const _dealSeller = '11111111-1111-1111-1111-111111111111';
const _cartSeller = '33333333-3333-3333-3333-333333333333';

const _single = CardModel(
  id: 42,
  category: CardCategory.pokemon,
  nameId: 'Lugia V',
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '025/165',
  rarity: 'SAR',
);

const _sealed = CardModel(
  id: 9000001,
  category: CardCategory.sealed,
  nameId: 'Booster Box',
  expansionCode: 'MA6',
  packSlug: 'ma6',
  collectorNumber: '',
  rarity: '',
);

CheckoutDeal _deal({int cardId = 42, String externalId = _dealId}) =>
    CheckoutDeal.fromCartRow({
      'external_id': externalId,
      'expires_at': '2099-10-08T10:00:00Z',
      'cart_snapshot': [
        {
          'seller_id': _dealSeller,
          'card_id': cardId,
          'card_name': 'Lugia V',
          'price': 300000,
          'quantity': 2,
          'condition': 'LP',
        },
      ],
    })!;

CartItem _item({CardModel card = _single, int id = 11}) => CartItem(
  cartItemId: id,
  quantity: 1,
  listing: ListingModel(
    id: id,
    sellerId: _cartSeller,
    slug: 'listing-$id',
    side: ListingSide.ask,
    price: 50000,
    condition: CardCondition.nm,
    quantity: 3,
    card: card,
    storeSlug: 'toko',
    storeName: 'Toko',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
  ),
);

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

class _RecordingApi extends PokepediaApi {
  _RecordingApi() : super(_client());

  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add((path, body));
    return const {'invoiceUrl': 'https://x', 'externalId': 'INV-1'};
  }
}

class _Gateway implements CheckoutGateway {
  final dealLookups = <List<String>?>[];
  final combined = <(List<int>, List<String>)>[];

  @override
  Future<CheckoutContext> fetchContext() async =>
      const CheckoutContext(phoneVerified: true);

  @override
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async => const {
    _dealSeller: SellerOrigin(cityId: '31.71', isActive: true),
    _cartSeller: SellerOrigin(cityId: '31.72', isActive: true),
  };

  @override
  Future<List<CheckoutDeal>> fetchDeals({List<String>? externalIds}) async {
    dealLookups.add(externalIds);
    return [_deal()];
  }

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
  }) async => const RateQuote(
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
  );

  @override
  Future<List<AvailableCoupon>> fetchAvailableCoupons({
    required int shippingTotal,
    required PaymentChannel? paymentChannel,
    required List<int> selectedCartItemIds,
    List<String> dealExternalIds = const [],
  }) async => const [];

  @override
  Future<CheckoutResult> submitCartWithDeals({
    required List<int> selectedCartItemIds,
    required List<String> dealExternalIds,
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    List<int> couponIds = const [],
  }) async {
    combined.add((selectedCartItemIds, dealExternalIds));
    return const CheckoutResult(invoiceUrl: 'https://checkout.xendit.co/x');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'buyer-1', email: 'buyer@pokepedia.id');
}

class _FakeCart extends CartNotifier {
  _FakeCart(this._items);

  final List<CartItem> _items;

  @override
  List<CartItem> build() => _items;
}

class _AcceptingRepository extends ProposalsRepository {
  _AcceptingRepository() : super(_client());

  @override
  Future<AcceptBidProposalResult> acceptBidProposal(
    String proposalSlug,
  ) async => const AcceptBidProposalResult(externalId: _dealId);

  @override
  Future<void> markProposalsSeen(Iterable<String> slugs) async {}
}

BidProposalModel _proposal() => BidProposalModel(
  slug: 'p1',
  card: _single,
  condition: CardCondition.nm,
  proposedQuantity: 1,
  sellerStoreName: 'Young',
  status: BidProposalStatus.pending,
  createdAt: DateTime(2026, 10, 6),
  expiresAt: DateTime(2099, 10, 8),
  seenAt: DateTime(2026, 10, 6),
);

void main() {
  group('accepting a proposal', () {
    final repository = ProposalsRepository(_client());
    // Built outside the fake-async zone: the client's auth refresh timer
    // would otherwise outlive the widget tree.
    final accepting = _AcceptingRepository();

    test('keeps the external id accept_bid_proposal hands back', () {
      final result = repository.parseAcceptBidProposal({
        'ok': true,
        'checkout_id': 5,
        'external_id': _dealId,
        'siblings_rejected': 0,
      });
      expect(result.error, isNull);
      expect(result.externalId, _dealId);
    });

    test('a refusal carries copy and no deal', () {
      final result = repository.parseAcceptBidProposal({
        'error': 'proposal_expired',
      });
      expect(result.error, isNotNull);
      expect(result.error, isNot(contains('_')));
      expect(result.externalId, isNull);
    });

    testWidgets('Bayar opens that deal, not the newest one for the card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1800, 3600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final gateway = _Gateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            proposalsRepositoryProvider.overrideWithValue(accepting),
            myBidsProvider.overrideWith((ref) async => const []),
            receivedProposalsProvider.overrideWith(
              (ref) async => [_proposal()],
            ),
            sentProposalsProvider.overrideWith((ref) async => const []),
            cardDetailProvider.overrideWith((ref, id) async => _single),
            checkoutGatewayProvider.overrideWithValue(gateway),
            addressesProvider.overrideWith((ref) async => const []),
            walletBalanceProvider.overrideWith((ref) async => 0),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const CardProposalsPage(cardId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terima'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();

      final page = tester.element(find.byType(CheckoutPage));
      final scoped = ProviderScope.containerOf(page);
      expect(scoped.read(checkoutDealIdsProvider), [_dealId]);
      expect(scoped.read(checkoutWithCartSelectionProvider), isFalse);
      expect(gateway.dealLookups, [
        [_dealId],
      ]);
    });
  });

  group('paying deals with the cart', () {
    test('the request names both the lines and the deals', () async {
      final api = _RecordingApi();
      await CheckoutGateway(api, _client()).submitCartWithDeals(
        selectedCartItemIds: const [11],
        dealExternalIds: const [_dealId],
        courierChoices: const [],
        deliveryAddressSlug: _address.slug,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.bni,
      );

      final (path, body) = api.calls.single;
      expect(path, '/api/cart/checkout');
      expect(body['selectedCartItemIds'], [11]);
      expect(body['selectedDealExternalIds'], [_dealId]);
    });

    test('no ticked lines still sends an empty selection', () async {
      final api = _RecordingApi();
      await CheckoutGateway(api, _client()).submitCartWithDeals(
        selectedCartItemIds: const [],
        dealExternalIds: const [_dealId],
        courierChoices: const [],
        deliveryAddressSlug: _address.slug,
        paymentMethod: PaymentMethod.wallet,
      );

      final (_, body) = api.calls.single;
      expect(body.containsKey('selectedCartItemIds'), isTrue);
      expect(body['selectedCartItemIds'], isEmpty);
    });

    test(
      'checkout prices, quotes and submits lines and deals together',
      () async {
        final gateway = _Gateway();
        final container = ProviderContainer(
          overrides: [
            checkoutGatewayProvider.overrideWithValue(gateway),
            checkoutDealIdsProvider.overrideWithValue(const [_dealId]),
            checkoutWithCartSelectionProvider.overrideWithValue(true),
            selectedCartItemsProvider.overrideWithValue([_item()]),
            walletBalanceProvider.overrideWith((ref) async => 0),
          ],
        );
        addTearDown(container.dispose);
        final visit = container.listen(checkoutProvider, (_, __) {});
        addTearDown(visit.close);
        final notifier = container.read(checkoutProvider.notifier);

        await notifier.loadContext();
        expect(notifier.isDealCheckout, isFalse);
        expect(notifier.sellerIds, [_cartSeller, _dealSeller]);
        expect(notifier.itemsSubtotal, 50000 + 600000);

        notifier.selectAddress(_address);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        await pumpEventQueue();
        notifier.selectXendit(PaymentChannel.bni);
        expect(notifier.blockedReason, isNull);

        await notifier.submit();
        expect(gateway.combined.single.$1, [11]);
        expect(gateway.combined.single.$2, [_dealId]);
      },
    );

    test('every deal starts ticked and unticks on its own', () async {
      final container = ProviderContainer(
        overrides: [
          cartDealsProvider.overrideWith(
            (ref) async => [_deal(), _deal(externalId: 'INV-BID-2')],
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cartDealSelectionProvider, (_, __) {});
      await container.read(cartDealsProvider.future);

      expect(container.read(cartDealSelectionProvider), {_dealId, 'INV-BID-2'});
      container.read(cartDealSelectionProvider.notifier).toggle(_dealId);
      expect(
        container.read(selectedCartDealsProvider).map((d) => d.externalId),
        ['INV-BID-2'],
      );
    });

    testWidgets('a deal-only seller shows up in the cart', (tester) async {
      await _pumpCart(tester, items: const [], deals: [_deal()]);
      expect(find.text('Bid Proposal'), findsOneWidget);
      expect(find.text('Lugia V'), findsOneWidget);
      expect(find.text('Subtotal (1 item)'), findsOneWidget);
    });
  });

  group('sealed products carry no condition', () {
    testWidgets('cart rows', (tester) async {
      await _pumpCart(
        tester,
        items: [_item(card: _sealed)],
        deals: [_deal(cardId: _sealed.id)],
      );
      expect(find.byType(ConditionBadge), findsNothing);
    });

    testWidgets('cart rows for singles keep it', (tester) async {
      await _pumpCart(tester, items: [_item()], deals: [_deal()]);
      expect(find.byType(ConditionBadge), findsNWidgets(2));
    });

    testWidgets('checkout rows', (tester) async {
      Future<void> pump(CardModel card) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SellerGroupCard(
                items: [_item(card: card)],
                deals: [_deal(cardId: card.id)],
                courierOptions: const [],
                selectedCourier: null,
                onSelectCourier: (_) {},
                insuranceEnabled: false,
                onToggleInsurance: (_) {},
                hasAddress: false,
              ),
            ),
          ),
        ),
      );

      await pump(_sealed);
      expect(find.byType(ConditionBadge), findsNothing);
      await pump(_single);
      expect(find.byType(ConditionBadge), findsNWidgets(2));
    });
  });

  group('SellerShipping.copyWith', () {
    test('takes a new reason, keeps the old one, or clears it', () {
      const shipping = SellerShipping(reason: RatesReason.noCoverage);
      expect(
        shipping.copyWith(reason: RatesReason.sellerRestricted).reason,
        RatesReason.sellerRestricted,
      );
      expect(shipping.copyWith(loading: true).reason, RatesReason.noCoverage);
      expect(shipping.copyWith(clearReason: true).reason, isNull);
    });
  });
}

Future<void> _pumpCart(
  WidgetTester tester, {
  required List<CartItem> items,
  required List<CheckoutDeal> deals,
}) async {
  tester.view.physicalSize = const Size(1800, 3600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartProvider.overrideWith(() => _FakeCart(items)),
        cartDealsProvider.overrideWith((ref) async => deals),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const CartPage()),
    ),
  );
  await tester.pumpAndSettle();
}
