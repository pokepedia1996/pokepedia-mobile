import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/features/cart/usecase/checkout_notifier.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/wallet_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// Checkout is a page, not a session. Entering it twice for two different
/// carts used to reuse the first visit's state, which is what left the
/// second one showing "0 layanan tersedia" — `selectAddress` early-returns
/// when the address hasn't changed, so nothing ever asked for quotes
/// against the new seller.
class _FakeGateway implements CheckoutGateway {
  @override
  Future<CheckoutContext> fetchContext() async =>
      const CheckoutContext(phoneVerified: true);

  @override
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async => const {};

  @override
  Future<PaymentChannel?> fetchLastPaidChannel() async => null;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

const _address = AddressModel(
  id: 1,
  slug: 'rumah',
  label: 'Rumah',
  contactName: 'Buyer',
  contactPhone: '0800',
  provinceId: '9',
  provinceName: 'Jawa Barat',
  cityId: '123',
  cityName: 'Bandung',
  districtId: '4567',
  district: 'Coblong',
  fullAddress: 'Jl. Test 1',
  isPrimary: true,
);

/// One line in the cart, so `blockedReason` gets past its empty-cart guard
/// and reaches the payment checks these are actually about.
final _cartItem = CartItem(
  cartItemId: 1,
  quantity: 1,
  listing: ListingModel(
    id: 1,
    sellerId: 'seller-1',
    slug: 'listing-1',
    side: ListingSide.ask,
    price: 50000,
    condition: CardCondition.nm,
    quantity: 3,
    status: ListingStatus.open,
    card: const CardModel(
      id: 1,
      category: CardCategory.pokemon,
      nameId: 'Pikachu',
      expansionCode: 'SV2a',
      packSlug: 'sv2a',
      collectorNumber: '025/165',
      rarity: 'Rare',
    ),
    storeSlug: 'toko',
    storeName: 'Toko',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
  ),
);

ProviderContainer _container({
  int walletBalance = 0,
  List<CartItem> cart = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      checkoutGatewayProvider.overrideWithValue(_FakeGateway()),
      // The cart itself is beside the point here; what matters is whether
      // the notifier starts over.
      selectedCartItemsProvider.overrideWithValue(cart),
      walletBalanceProvider.overrideWith((ref) async => walletBalance),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('leaving the page drops the checkout state', () async {
    final container = _container();

    // A visit: the page watches the provider, and an address is chosen.
    final visit = container.listen(checkoutProvider, (_, __) {});
    // `build` kicks off loadContext in a microtask. Settle it before doing
    // anything else: leaving it in flight makes what happens at close time
    // depend on how loaded the machine is, which is what made this test flake
    // when the suite runs files in parallel.
    await container.read(checkoutProvider.notifier).loadContext();
    container.read(checkoutProvider.notifier).selectAddress(_address);
    expect(container.read(checkoutProvider).address, isNotNull);

    // Leaving pops the page, which drops the last listener.
    visit.close();
    await Future<void>.delayed(Duration.zero);

    // Coming back rebuilds from nothing, so every seller in the new cart
    // gets quoted instead of inheriting an empty courier list.
    final second = container.listen(checkoutProvider, (_, __) {});
    addTearDown(second.close);
    expect(container.read(checkoutProvider).address, isNull);
    expect(container.read(checkoutProvider).shippingBySeller, isEmpty);
  });

  test('state survives while the page is still on screen', () async {
    final container = _container();
    final visit = container.listen(checkoutProvider, (_, __) {});
    addTearDown(visit.close);

    await container.read(checkoutProvider.notifier).loadContext();
    container.read(checkoutProvider.notifier).selectAddress(_address);
    await Future<void>.delayed(Duration.zero);

    // A rebuild mid-checkout must not throw the buyer's choices away.
    expect(container.read(checkoutProvider).address?.id, _address.id);
  });

  test('an unread balance is unknown, not empty', () async {
    final container = _container(
      walletBalance: 5000000,
      cart: [_cartItem],
    );
    final visit = container.listen(checkoutProvider, (_, __) {});
    addTearDown(visit.close);

    // Null, not 0. `walletBalanceProvider` is autoDispose, so checkout opens
    // on a balance nobody has fetched yet — and calling that zero is what
    // greyed saldo out as "tidak cukup" on a wallet with money in it.
    expect(container.read(checkoutProvider).walletBalance, isNull);

    final notifier = container.read(checkoutProvider.notifier);
    notifier.selectAddress(_address);
    notifier.selectWallet();
    // Blocked while unknown, but for the honest reason.
    expect(notifier.blockedReason, 'Memuat saldo...');
  });

  test('the balance lands once the wallet answers', () async {
    final container = _container(walletBalance: 250000);
    final visit = container.listen(checkoutProvider, (_, __) {});
    addTearDown(visit.close);

    // Checkout's own `ref.listen` holds the autoDispose provider open, so
    // this is the same fetch the page waits on rather than a second one.
    await container.read(walletBalanceProvider.future);
    await pumpEventQueue();

    expect(container.read(checkoutProvider).walletBalance, 250000);
  });
}
