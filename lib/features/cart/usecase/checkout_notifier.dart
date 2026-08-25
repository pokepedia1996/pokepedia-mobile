import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../account/repository/models/address_model.dart';
import '../repository/checkout_gateway.dart';
import '../repository/checkout_pricing.dart';
import '../repository/models/cart_item.dart';
import '../repository/models/checkout_models.dart';
import 'cart_notifier.dart';
import 'cart_selection.dart';

/// Per-seller shipping state. Ports `SellerShipping` from
/// `features/checkout/types.ts`.
class SellerShipping {
  const SellerShipping({
    this.loading = false,
    this.options = const [],
    this.selected,
    this.error,
  });

  final bool loading;
  final List<CourierOption> options;
  final CourierOption? selected;
  final String? error;

  SellerShipping copyWith({
    bool? loading,
    List<CourierOption>? options,
    CourierOption? selected,
    String? error,
    bool clearSelected = false,
    bool clearError = false,
  }) {
    return SellerShipping(
      loading: loading ?? this.loading,
      options: options ?? this.options,
      selected: clearSelected ? null : (selected ?? this.selected),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CheckoutState {
  const CheckoutState({
    this.address,
    this.shippingBySeller = const {},
    this.insuranceBySeller = const {},
    this.coupon,
    this.couponError,
    this.couponLoading = false,
    this.buyerNote = '',
    this.paymentMethod = PaymentMethod.xendit,
    this.paymentChannel,
    this.walletBalance = 0,
    this.phoneVerified = true,
    this.contextLoading = true,
    this.contextError,
    this.submitting = false,
  });

  final AddressModel? address;
  final Map<String, SellerShipping> shippingBySeller;
  final Map<String, bool> insuranceBySeller;
  final AppliedCoupon? coupon;
  final String? couponError;
  final bool couponLoading;
  final String buyerNote;
  final PaymentMethod paymentMethod;
  final PaymentChannel? paymentChannel;
  final int walletBalance;

  /// The server rejects an unverified buyer, so the button is gated locally
  /// rather than letting the submit come back 403.
  final bool phoneVerified;

  final bool contextLoading;

  /// Set when the buyer's checkout context couldn't be read. Rates are
  /// fetched separately and report their own errors per seller.
  final String? contextError;

  final bool submitting;

  CheckoutState copyWith({
    AddressModel? address,
    Map<String, SellerShipping>? shippingBySeller,
    Map<String, bool>? insuranceBySeller,
    AppliedCoupon? coupon,
    String? couponError,
    bool? couponLoading,
    String? buyerNote,
    PaymentMethod? paymentMethod,
    PaymentChannel? paymentChannel,
    int? walletBalance,
    bool? phoneVerified,
    bool? contextLoading,
    String? contextError,
    bool? submitting,
    bool clearCoupon = false,
    bool clearCouponError = false,
    bool clearChannel = false,
    bool clearContextError = false,
  }) {
    return CheckoutState(
      address: address ?? this.address,
      shippingBySeller: shippingBySeller ?? this.shippingBySeller,
      insuranceBySeller: insuranceBySeller ?? this.insuranceBySeller,
      coupon: clearCoupon ? null : (coupon ?? this.coupon),
      couponError: clearCouponError ? null : (couponError ?? this.couponError),
      couponLoading: couponLoading ?? this.couponLoading,
      buyerNote: buyerNote ?? this.buyerNote,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentChannel: clearChannel
          ? null
          : (paymentChannel ?? this.paymentChannel),
      walletBalance: walletBalance ?? this.walletBalance,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      contextLoading: contextLoading ?? this.contextLoading,
      contextError: clearContextError
          ? null
          : (contextError ?? this.contextError),
      submitting: submitting ?? this.submitting,
    );
  }
}

/// Drives the native WTS checkout: address, per-seller courier and
/// insurance, coupon, note, payment choice, and the totals that follow from
/// them. Ports `checkout-client.tsx` together with the `useShippingRates`,
/// `useInsurance`, `usePayment` and `useCoupon` hooks it composes.
class CheckoutNotifier extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    Future.microtask(loadContext);
    return const CheckoutState();
  }

  List<CartItem> get _items => ref.read(selectedCartItemsProvider);

  Map<String, List<CartItem>> get _itemsBySeller {
    final map = <String, List<CartItem>>{};
    for (final item in _items) {
      (map[item.listing.sellerId] ??= []).add(item);
    }
    return map;
  }

  int subtotalForSeller(String sellerId) =>
      (_itemsBySeller[sellerId] ?? const [])
          .fold(0, (sum, item) => sum + item.subtotal);

  Future<void> loadContext() async {
    state = state.copyWith(contextLoading: true, clearContextError: true);
    try {
      final context = await ref.read(checkoutGatewayProvider).fetchContext();
      state = state.copyWith(
        contextLoading: false,
        phoneVerified: context.phoneVerified,
      );
      await _refreshAllRates();
    } on ApiException catch (e) {
      // Leaves `phoneVerified` alone: without the server we can't tell, and
      // blocking the buyer on an unknown is worse than letting the handoff
      // surface the real reason.
      state = state.copyWith(contextLoading: false, contextError: e.message);
    }
  }

  /// Coalesces address changes so a burst of selections costs one round of
  /// quotes, not one per tap.
  Timer? _rateDebounce;

  void selectAddress(AddressModel address) {
    if (state.address?.id == address.id) return;
    state = state.copyWith(address: address);

    // A different destination invalidates every quote — but each seller is a
    // separate call, and `/api/shipping/rates` is budgeted at 30/60s because
    // it fans out to billable Biteship. A four-seller cart is four calls per
    // address change, so settle before spending them.
    _rateDebounce?.cancel();
    _rateDebounce = Timer(
      const Duration(milliseconds: 400),
      _refreshAllRates,
    );
  }

  /// Ports `fetchRatesForSeller`.
  Future<void> fetchRatesForSeller(String sellerId) async {
    final destination = state.address;
    if (destination == null) return;

    _setShipping(sellerId, const SellerShipping(loading: true));

    final sellerItems = _itemsBySeller[sellerId] ?? const [];
    final quantity = sellerItems.fold(0, (sum, item) => sum + item.quantity);
    final subtotal = sellerItems.fold(0, (sum, item) => sum + item.subtotal);

    try {
      final options = await ref.read(checkoutGatewayProvider).fetchRates(
        sellerId: sellerId,
        addressSlug: destination.slug,
        quantity: quantity < 1 ? 1 : quantity,
        itemValue: subtotal,
      );

      // Instant couriers need a map pinpoint on the destination; without one
      // they're still listed but never preselected, matching the web.
      final eligible = destination.hasPinpoint
          ? options
          : options.where((o) => o.bucket != CourierBucket.instant).toList();
      final preselected = eligible.isNotEmpty
          ? eligible.first
          : (options.isNotEmpty ? options.first : null);

      _setShipping(
        sellerId,
        SellerShipping(options: options, selected: preselected),
      );
      _syncMandatoryInsurance(sellerId);
    } on ApiException catch (e) {
      _setShipping(sellerId, SellerShipping(error: e.message));
    }
  }

  void selectCourier(String sellerId, CourierOption option) {
    final current = state.shippingBySeller[sellerId] ?? const SellerShipping();
    _setShipping(sellerId, current.copyWith(selected: option));
    _syncMandatoryInsurance(sellerId);
  }

  /// Ports `isInsuranceMandatoryFor`: above Rp500.000 the buyer doesn't get
  /// to decline, and the server enforces the same rule at submit time.
  bool isInsuranceMandatoryFor(String sellerId) =>
      isInsuranceMandatory(subtotalForSeller(sellerId));

  void toggleInsurance(String sellerId, bool enabled) {
    if (isInsuranceMandatoryFor(sellerId) && !enabled) return;
    state = state.copyWith(
      insuranceBySeller: {...state.insuranceBySeller, sellerId: enabled},
    );
  }

  void setBuyerNote(String note) => state = state.copyWith(buyerNote: note);

  void selectXendit(PaymentChannel channel) {
    state = state.copyWith(
      paymentMethod: PaymentMethod.xendit,
      paymentChannel: channel,
    );
  }

  void selectWallet() {
    state = state.copyWith(
      paymentMethod: PaymentMethod.wallet,
      clearChannel: true,
      // A wallet payment charges no gateway fee, so a fee-waiver coupon has
      // nothing left to waive.
      clearCoupon: state.coupon?.waivesGatewayFee ?? false,
    );
  }

  void setWalletBalance(int balance) =>
      state = state.copyWith(walletBalance: balance);

  Future<void> applyCoupon(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(couponLoading: true, clearCouponError: true);
    final result = await ref.read(cartRepositoryProvider).applyCoupon(
      code: trimmed,
      itemsSubtotal: itemsSubtotal,
    );
    state = state.copyWith(
      couponLoading: false,
      coupon: result.coupon,
      couponError: result.error,
      clearCoupon: result.coupon == null,
      clearCouponError: result.error == null,
    );
  }

  void removeCoupon() =>
      state = state.copyWith(clearCoupon: true, clearCouponError: true);

  int get itemsSubtotal =>
      _items.fold(0, (sum, item) => sum + item.subtotal);

  int get shippingTotal => state.shippingBySeller.values
      .fold(0, (sum, shipping) => sum + (shipping.selected?.cost ?? 0));

  /// Ports `computeInsuranceTotal` — only charged where the buyer asked for
  /// it *and* the chosen service actually supports it.
  int get insuranceTotal {
    var total = 0;
    for (final entry in state.shippingBySeller.entries) {
      final selected = entry.value.selected;
      final wanted = state.insuranceBySeller[entry.key] ?? false;
      if (selected != null && wanted && selected.insuranceAvailable) {
        total += selected.insuranceFee;
      }
    }
    return total;
  }

  CheckoutTotals get totals => computeCheckoutTotals(
    itemsSubtotal: itemsSubtotal,
    shippingTotal: shippingTotal,
    insuranceTotal: insuranceTotal,
    paymentMethod: state.paymentMethod,
    paymentChannel: state.paymentChannel,
    appliedCoupon: state.coupon,
  );

  /// Every reason the pay button stays disabled, in the same order the web
  /// evaluates them.
  String? get blockedReason {
    if (_items.isEmpty) return 'Keranjang kosong.';
    if (state.address == null) return 'Pilih alamat pengiriman dulu.';
    if (!state.phoneVerified) {
      return 'Verifikasi nomor HP dulu di pengaturan akun.';
    }
    if (state.paymentMethod == PaymentMethod.xendit &&
        state.paymentChannel == null) {
      return 'Pilih metode pembayaran.';
    }
    if (state.paymentMethod == PaymentMethod.wallet &&
        state.walletBalance < totals.grandTotalBeforeFee) {
      return 'Saldo dompet tidak cukup.';
    }
    for (final sellerId in _itemsBySeller.keys) {
      if (state.shippingBySeller[sellerId]?.selected == null) {
        return 'Pilih kurir untuk semua toko.';
      }
    }
    return null;
  }

  /// Submits and returns where to go next: Xendit's hosted invoice for a
  /// card payment, or null when the wallet settled it outright. Throws
  /// [ApiException] so the page can show the server's own message.
  Future<CheckoutResult> submit() async {
    state = state.copyWith(submitting: true);
    try {
      final choices = <CourierChoice>[];
      for (final entry in state.shippingBySeller.entries) {
        final selected = entry.value.selected;
        if (selected == null) continue;
        final mandatory = isInsuranceMandatoryFor(entry.key);
        choices.add(
          CourierChoice(
            sellerId: entry.key,
            courier: selected.courier,
            service: selected.service,
            insuranceEnabled:
                mandatory || (state.insuranceBySeller[entry.key] ?? false),
          ),
        );
      }

      return await ref.read(checkoutGatewayProvider).submit(
        courierChoices: choices,
        deliveryAddressSlug: state.address!.slug,
        paymentMethod: state.paymentMethod,
        paymentChannel: state.paymentChannel,
        buyerNote: state.buyerNote,
        couponCode: state.coupon?.code,
        selectedCartItemIds: [for (final item in _items) item.cartItemId],
      );
    } finally {
      state = state.copyWith(submitting: false);
    }
  }

  Future<void> _refreshAllRates() async {
    if (state.address == null) return;
    await Future.wait([
      for (final sellerId in _itemsBySeller.keys) fetchRatesForSeller(sellerId),
    ]);
  }

  void _setShipping(String sellerId, SellerShipping shipping) {
    state = state.copyWith(
      shippingBySeller: {...state.shippingBySeller, sellerId: shipping},
    );
  }

  /// Keeps the toggle honest: over the threshold insurance is forced on, and
  /// a service that can't insure can't have it on either.
  void _syncMandatoryInsurance(String sellerId) {
    final selected = state.shippingBySeller[sellerId]?.selected;
    final mandatory = isInsuranceMandatoryFor(sellerId);
    final supported = selected?.insuranceAvailable ?? false;
    final next = mandatory && supported;
    if (next == (state.insuranceBySeller[sellerId] ?? false)) return;
    if (!mandatory && !supported) {
      state = state.copyWith(
        insuranceBySeller: {...state.insuranceBySeller, sellerId: false},
      );
      return;
    }
    if (next) {
      state = state.copyWith(
        insuranceBySeller: {...state.insuranceBySeller, sellerId: true},
      );
    }
  }
}

final checkoutProvider = NotifierProvider<CheckoutNotifier, CheckoutState>(
  CheckoutNotifier.new,
);
