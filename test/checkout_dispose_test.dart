import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_gateway.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';
import 'package:pokepedia_mobile/features/cart/usecase/cart_selection.dart';
import 'package:pokepedia_mobile/features/cart/usecase/checkout_notifier.dart';

class _FakeGateway implements CheckoutGateway {
  @override
  Future<CheckoutContext> fetchContext() async =>
      const CheckoutContext(phoneVerified: true);
  @override
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async => const {};
  @override
  Future<PaymentChannel?> fetchLastPaidChannel() async => null;
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

const _address = AddressModel(
  id: 1,
  slug: 'rumah',
  label: 'Rumah',
  contactName: 'B',
  contactPhone: '0',
  provinceId: '9',
  provinceName: 'Jabar',
  cityId: '123',
  cityName: 'Bandung',
  districtId: '4567',
  district: 'Coblong',
  fullAddress: 'Jl. 1',
  isPrimary: true,
);

/// Checkout starts work that can outlive it: `build` fires two microtasks and
/// `selectAddress` a 400ms debounce. A buyer who backs out before any of them
/// land used to crash the zone with "Tried to read a provider from a
/// ProviderContainer that was already disposed" — which surfaced first as a
/// flaky suite, since whether it happened depended on machine load.
void main() {
  test(
    'leaving inside the rate debounce does not read a dead container',
    () async {
      final container = ProviderContainer(
        overrides: [
          checkoutGatewayProvider.overrideWithValue(_FakeGateway()),
          selectedCartItemsProvider.overrideWithValue(const []),
        ],
      );
      final sub = container.listen(checkoutProvider, (_, __) {});

      // The 400ms debounce is now in flight.
      container.read(checkoutProvider.notifier).selectAddress(_address);
      sub.close();
      container.dispose();

      // Long enough for the timer to have fired had it survived.
      await Future<void>.delayed(const Duration(milliseconds: 600));
    },
  );

  test('leaving before the opening microtasks land is also safe', () async {
    final container = ProviderContainer(
      overrides: [
        checkoutGatewayProvider.overrideWithValue(_FakeGateway()),
        selectedCartItemsProvider.overrideWithValue(const []),
      ],
    );
    // Built and torn down in the same turn, so `loadContext` and
    // `loadLastPaidChannel` both run against a container that is already gone.
    final sub = container.listen(checkoutProvider, (_, __) {});
    sub.close();
    container.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
}
