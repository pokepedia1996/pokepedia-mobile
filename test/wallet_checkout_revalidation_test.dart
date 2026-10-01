import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/features/cart/usecase/checkout_notifier.dart';
import 'package:pokepedia_mobile/features/orders/usecase/orders_notifier.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/wallet_notifier.dart';

/// Paying from saldo is settled by the time `/api/cart/checkout` answers:
/// `pay_checkout_with_wallet` debits through `credit_wallet` and writes the
/// ledger row before responding. The app then has to stop believing what it
/// cached, or the buyer sees the old balance on a spent wallet.
class _FakeGateway implements CheckoutGateway {
  @override
  Future<CheckoutContext> fetchContext() async =>
      const CheckoutContext(phoneVerified: true);

  @override
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async => const {};

  @override
  Future<PaymentChannel?> fetchLastPaidChannel() async => null;

  @override
  Future<CheckoutResult> submit({
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    String? couponCode,
    List<int> selectedCartItemIds = const [],
  }) async => const CheckoutResult(redirect: '/orders');

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

void main() {
  /// Counts how many times each provider actually rebuilds, which is what an
  /// invalidate costs and what a stale screen is missing.
  late int balanceBuilds;
  late int activityBuilds;
  late int orderBuilds;

  ProviderContainer container() {
    balanceBuilds = 0;
    activityBuilds = 0;
    orderBuilds = 0;
    final c = ProviderContainer(
      overrides: [
        checkoutGatewayProvider.overrideWithValue(_FakeGateway()),
        selectedCartItemsProvider.overrideWithValue(const []),
        walletBalanceProvider.overrideWith((ref) async {
          balanceBuilds++;
          return 5000000;
        }),
        walletActivityProvider.overrideWith((ref, bucket) async {
          activityBuilds++;
          return const <WalletActivity>[];
        }),
        ordersProvider.overrideWith((ref) async {
          orderBuilds++;
          return const [];
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Holds all three open for the length of the test. `walletBalanceProvider`
  /// is autoDispose, so without a standing listener it can be torn down and
  /// rebuilt between reads and the counts stop meaning anything — a live
  /// screen watching them is what this stands in for.
  void hold(ProviderContainer c) {
    for (final sub in [
      c.listen(walletBalanceProvider, (_, __) {}),
      c.listen(walletActivityProvider(WalletBucket.all), (_, __) {}),
      c.listen(ordersProvider, (_, __) {}),
    ]) {
      addTearDown(sub.close);
    }
  }

  Future<void> warmUp(ProviderContainer c) async {
    await c.read(walletBalanceProvider.future);
    await c.read(walletActivityProvider(WalletBucket.all).future);
    await c.read(ordersProvider.future);
  }

  test('a saldo checkout revalidates the wallet and the order list', () async {
    final c = container();
    final sub = c.listen(checkoutProvider, (_, __) {});
    addTearDown(sub.close);
    hold(c);
    await warmUp(c);
    expect(balanceBuilds, 1);

    final notifier = c.read(checkoutProvider.notifier);
    notifier.selectAddress(_address);
    notifier.selectWallet();
    await notifier.submit();

    // Invalidated, so the next read refetches rather than replaying the
    // balance from before the money was spent.
    await warmUp(c);
    expect(balanceBuilds, 2, reason: 'saldo must be re-read after settlement');
    expect(activityBuilds, 2, reason: 'the ledger gained a row');
    expect(orderBuilds, 2, reason: 'the order the buyer just placed');
  });

  test('a card checkout leaves them alone', () async {
    final c = container();
    final sub = c.listen(checkoutProvider, (_, __) {});
    addTearDown(sub.close);
    hold(c);
    await warmUp(c);

    final notifier = c.read(checkoutProvider.notifier);
    notifier.selectAddress(_address);
    notifier.selectXendit(PaymentChannel.qris);
    await notifier.submit();

    // Still unpaid at this point — the webhook decides, and revalidating here
    // would only show the buyer an unchanged balance as if it were fresh.
    await warmUp(c);
    expect(balanceBuilds, 1);
    expect(activityBuilds, 1);
    expect(orderBuilds, 1);
  });
}
