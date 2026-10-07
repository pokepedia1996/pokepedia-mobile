import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../account/repository/models/address_model.dart';
import '../../orders/usecase/orders_notifier.dart';
import '../../wallet/usecase/wallet_notifier.dart';
import '../repository/checkout_gateway.dart';
import '../repository/checkout_pricing.dart';
import '../repository/coupon_rules.dart';
import '../repository/models/cart_item.dart';
import '../repository/models/checkout_deal.dart';
import '../repository/models/checkout_models.dart';
import 'cart_selection.dart';
import '../../../core/errors/user_message.dart';

/// Per-seller shipping state. Ports `SellerShipping` from
/// `features/checkout/types.ts`.
class SellerShipping {
  const SellerShipping({
    this.loading = false,
    this.options = const [],
    this.selected,
    this.error,
    this.reason,
  });

  final bool loading;
  final List<CourierOption> options;
  final CourierOption? selected;
  final String? error;

  /// Why [options] is short or empty, as `/api/shipping/rates` reported it.
  final RatesReason? reason;

  SellerShipping copyWith({
    bool? loading,
    List<CourierOption>? options,
    CourierOption? selected,
    String? error,
    RatesReason? reason,
    bool clearSelected = false,
    bool clearError = false,
    bool clearReason = false,
  }) {
    return SellerShipping(
      loading: loading ?? this.loading,
      options: options ?? this.options,
      selected: clearSelected ? null : (selected ?? this.selected),
      error: clearError ? null : (error ?? this.error),
      reason: clearReason ? null : (reason ?? this.reason),
    );
  }
}

class CheckoutState {
  const CheckoutState({
    this.address,
    this.shippingBySeller = const {},
    this.insuranceBySeller = const {},
    this.couponCatalog = const [],
    this.couponOverrides = const CouponOverrides(subtotal: 0),
    this.couponsLoading = false,
    this.couponsError = false,
    this.couponNotice,
    this.buyerNote = '',
    this.paymentMethod = PaymentMethod.xendit,
    this.paymentChannel,
    this.walletBalance,
    this.lastPaidChannel,
    this.paymentTouched = false,
    this.sellerOrigins = const {},
    this.phoneVerified = true,
    this.contextLoading = true,
    this.contextError,
    this.submitting = false,
    this.deals = const [],
  });

  final AddressModel? address;
  final Map<String, SellerShipping> shippingBySeller;
  final Map<String, bool> insuranceBySeller;

  /// Every coupon `/api/coupons/available` listed for this checkout,
  /// eligible or not. What is *applied* is derived from this and
  /// [couponOverrides] by [CheckoutNotifier.coupons].
  final List<AvailableCoupon> couponCatalog;
  final CouponOverrides couponOverrides;
  final bool couponsLoading;
  final bool couponsError;

  /// Why the server just refused a coupon at submit, shown by the picker
  /// until the buyer changes their selection.
  final String? couponNotice;
  final String buyerNote;
  final PaymentMethod paymentMethod;
  final PaymentChannel? paymentChannel;

  /// Null until the wallet has answered. Distinct from zero on purpose:
  /// an unknown balance must not read as an empty one, or saldo shows up
  /// greyed out as "tidak cukup" for the moment before it loads.
  final int? walletBalance;

  /// The channel the buyer paid with last time, used to preselect a VA bank
  /// rather than always landing them on the first one in the list. Null
  /// until it has been read, and for a buyer who last paid from saldo.
  final PaymentChannel? lastPaidChannel;

  /// Whether the buyer has picked a payment method themselves. Auto-select
  /// stops the moment they do — a choice that keeps being overwritten by a
  /// changing total is worse than no default at all.
  final bool paymentTouched;

  /// Where each seller ships from, keyed by seller id. Needed before a quote
  /// can be asked for, and only the server can read it.
  final Map<String, SellerOrigin> sellerOrigins;

  /// The server rejects an unverified buyer, so the button is gated locally
  /// rather than letting the submit come back 403.
  final bool phoneVerified;

  final bool contextLoading;

  /// Set when the buyer's checkout context couldn't be read. Rates are
  /// fetched separately and report their own errors per seller.
  final String? contextError;

  final bool submitting;

  /// The accepted bid proposals being paid, loaded with the checkout
  /// context. Empty outside a deal checkout.
  final List<CheckoutDeal> deals;

  CheckoutState copyWith({
    AddressModel? address,
    Map<String, SellerShipping>? shippingBySeller,
    Map<String, bool>? insuranceBySeller,
    List<AvailableCoupon>? couponCatalog,
    CouponOverrides? couponOverrides,
    bool? couponsLoading,
    bool? couponsError,
    String? couponNotice,
    String? buyerNote,
    PaymentMethod? paymentMethod,
    PaymentChannel? paymentChannel,
    int? walletBalance,
    PaymentChannel? lastPaidChannel,
    bool? paymentTouched,
    Map<String, SellerOrigin>? sellerOrigins,
    bool? phoneVerified,
    bool? contextLoading,
    String? contextError,
    bool? submitting,
    List<CheckoutDeal>? deals,
    bool clearCouponNotice = false,
    bool clearChannel = false,
    bool clearContextError = false,
  }) {
    return CheckoutState(
      address: address ?? this.address,
      shippingBySeller: shippingBySeller ?? this.shippingBySeller,
      insuranceBySeller: insuranceBySeller ?? this.insuranceBySeller,
      couponCatalog: couponCatalog ?? this.couponCatalog,
      couponOverrides: couponOverrides ?? this.couponOverrides,
      couponsLoading: couponsLoading ?? this.couponsLoading,
      couponsError: couponsError ?? this.couponsError,
      couponNotice: clearCouponNotice
          ? null
          : (couponNotice ?? this.couponNotice),
      buyerNote: buyerNote ?? this.buyerNote,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentChannel: clearChannel
          ? null
          : (paymentChannel ?? this.paymentChannel),
      walletBalance: walletBalance ?? this.walletBalance,
      lastPaidChannel: lastPaidChannel ?? this.lastPaidChannel,
      paymentTouched: paymentTouched ?? this.paymentTouched,
      sellerOrigins: sellerOrigins ?? this.sellerOrigins,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      contextLoading: contextLoading ?? this.contextLoading,
      contextError: clearContextError
          ? null
          : (contextError ?? this.contextError),
      submitting: submitting ?? this.submitting,
      deals: deals ?? this.deals,
    );
  }
}

/// The accepted bid proposals a checkout pays for, by external id.
///
/// Empty for a cart checkout. A deal checkout overrides it in the
/// `ProviderScope` around its page — `dealCheckoutRoute` — which is what web
/// carries in `?d=`, so [checkoutProvider] is scoped along with it.
final checkoutDealIdsProvider = Provider<List<String>>((ref) => const []);

/// Whether the deals of [checkoutDealIdsProvider] are paid together with the
/// lines ticked in the cart — web's `?s=&d=` from the cart page — rather
/// than on their own. Scoped by `dealCheckoutRoute` alongside the ids.
final checkoutWithCartSelectionProvider = Provider<bool>((ref) => false);

/// Drives the native WTS checkout: address, per-seller courier and
/// insurance, coupons, note, payment choice, and the totals that follow from
/// them. Ports `checkout-client.tsx` together with the `useShippingRates`,
/// `useInsurance`, `usePayment`, `useCouponCatalog` and `useCoupon` hooks it
/// composes.
class CheckoutNotifier extends AutoDisposeNotifier<CheckoutState> {
  @override
  CheckoutState build() {
    _dealIds = ref.watch(checkoutDealIdsProvider);
    _withCartSelection = ref.watch(checkoutWithCartSelectionProvider);
    Future.microtask(loadContext);
    Future.microtask(loadLastPaidChannel);

    // Follow the wallet, and seed from it in case it is already resolved.
    // `ref.listen` fires on change only, so on its own it never delivered a
    // value that had settled before checkout opened — which is how the buyer
    // reached this page with the default balance and saldo greyed out. The
    // listen also keeps the autoDispose provider alive for as long as
    // checkout is on screen.
    //
    // Seeded with `read` rather than `watch`: watching would rebuild the
    // whole CheckoutState when the balance moves, discarding the address,
    // courier and payment choices the buyer had already made.
    ref.listen(walletBalanceProvider, (_, next) {
      final balance = next.valueOrNull;
      if (balance != null) setWalletBalance(balance);
    });

    // The rate debounce outlives the notifier otherwise. A buyer who picks an
    // address and leaves checkout inside 400ms left a timer behind that woke
    // up, called `_refreshAllRates`, and read `selectedCartItemsProvider` off
    // a container that no longer exists — "Tried to read a provider from a
    // ProviderContainer that was already disposed".
    ref.onDispose(() {
      _disposed = true;
      _rateDebounce?.cancel();
      _rateDebounce = null;
      _couponDebounce?.cancel();
      _couponDebounce = null;
    });
    return CheckoutState(
      walletBalance: ref.read(walletBalanceProvider).valueOrNull,
    );
  }

  /// Whether checkout has been left. `build` starts two microtasks and
  /// `selectAddress` a 400ms timer, any of which can come back after the
  /// buyer has popped the page — and reading `ref` then throws "Tried to read
  /// a provider from a ProviderContainer that was already disposed". Every
  /// continuation checks this before touching `ref` or `state`.
  bool _disposed = false;

  List<String> _dealIds = const [];
  bool _withCartSelection = false;

  /// A deal checkout pays for its deals alone, as web's proposal-only
  /// checkout does — never the cart lines sitting beside them.
  bool get isDealCheckout => _dealIds.isNotEmpty && !_withCartSelection;

  /// The deals actually loaded, which is what gets priced and invoiced: one
  /// that lapsed since the cart page was read is left out rather than
  /// failing the whole submit.
  List<String> get _loadedDealIds => [
    for (final deal in state.deals) deal.externalId,
  ];

  List<CartItem> get _items =>
      isDealCheckout ? const [] : ref.read(selectedCartItemsProvider);

  Map<String, List<CartItem>> get _itemsBySeller {
    final map = <String, List<CartItem>>{};
    for (final item in _items) {
      (map[item.listing.sellerId] ??= []).add(item);
    }
    return map;
  }

  /// Every seller that ships a parcel: cart lines first, then the deal-only
  /// ones — `allSellerGroups` in `checkout-client.tsx`.
  List<String> get sellerIds => {
    ..._itemsBySeller.keys,
    for (final deal in state.deals) deal.sellerId,
  }.toList();

  int _dealSubtotalForSeller(String sellerId) => state.deals
      .where((deal) => deal.sellerId == sellerId)
      .fold(0, (sum, deal) => sum + deal.subtotal);

  /// Cart lines plus deals — the route's `sellerTotalValue`, which is what it
  /// both declares to the courier and holds the insurance threshold against.
  int subtotalForSeller(String sellerId) =>
      (_itemsBySeller[sellerId] ?? const []).fold(
        0,
        (sum, item) => sum + item.subtotal,
      ) +
      _dealSubtotalForSeller(sellerId);

  Future<void> loadContext() async {
    if (_disposed) return;
    state = state.copyWith(contextLoading: true, clearContextError: true);
    final gateway = ref.read(checkoutGatewayProvider);
    try {
      // Both before the first quote: an origin is as necessary to price a
      // parcel as the destination is.
      final results = await Future.wait([
        gateway.fetchContext(),
        gateway.fetchSellerOrigins(),
        if (_dealIds.isNotEmpty) gateway.fetchDeals(externalIds: _dealIds),
      ]);
      if (_disposed) return;
      state = state.copyWith(
        contextLoading: false,
        phoneVerified: (results[0] as CheckoutContext).phoneVerified,
        sellerOrigins: results[1] as Map<String, SellerOrigin>,
        deals: _dealIds.isNotEmpty ? results[2] as List<CheckoutDeal> : null,
      );
      await _refreshAllRates();
    } on ApiException catch (e) {
      if (_disposed) return;
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
    _rateDebounce = Timer(const Duration(milliseconds: 400), _refreshAllRates);
  }

  /// Ports `fetchRatesForSeller`.
  Future<void> fetchRatesForSeller(String sellerId) async {
    if (_disposed) return;
    final destination = state.address;
    if (destination == null) return;

    _setShipping(sellerId, const SellerShipping(loading: true));

    var origins = state.sellerOrigins;
    if (origins.isEmpty) {
      // One call covers the whole cart, so a per-seller retry re-fetches it
      // rather than reporting a missing store address that is really a
      // missing round trip.
      try {
        origins = await ref.read(checkoutGatewayProvider).fetchSellerOrigins();
        state = state.copyWith(sellerOrigins: origins);
      } on ApiException catch (e) {
        _setShipping(sellerId, SellerShipping(error: userFacingError(e)));
        return;
      }
    }

    final origin = origins[sellerId];
    final originCityId = origin?.cityId;
    if (originCityId == null || originCityId.isEmpty) {
      // Web simply skips the call; on a phone an empty courier list with no
      // explanation reads as a bug, so say whose side it is on. A deal seller
      // missing from `sellerOrigins` is a gap in `GET /api/cart`, which only
      // resolves the sellers of cart lines, not a store left unfinished.
      _setShipping(
        sellerId,
        SellerShipping(
          error: origin == null && !_itemsBySeller.containsKey(sellerId)
              ? 'Alamat pengirim toko ini belum bisa dimuat. Coba lagi nanti.'
              : 'Toko ini belum melengkapi alamat pengiriman.',
        ),
      );
      return;
    }
    if (destination.cityId.isEmpty) {
      _setShipping(
        sellerId,
        const SellerShipping(error: 'Alamat tujuan belum lengkap.'),
      );
      return;
    }

    // Weighed from cart lines only, as the route's `totalQty` is, so the
    // preview and the submit-time quote see the same parcel; valued with the
    // deals included, as `declaredItemValue` is.
    final sellerItems = _itemsBySeller[sellerId] ?? const [];
    final quantity = sellerItems.fold(0, (sum, item) => sum + item.quantity);
    final subtotal = subtotalForSeller(sellerId);

    try {
      final quote = await ref
          .read(checkoutGatewayProvider)
          .fetchRateQuote(
            originCityId: originCityId,
            destinationCityId: destination.cityId,
            quantity: quantity < 1 ? 1 : quantity,
            itemValue: subtotal,
            originLat: origin?.pickupLat,
            originLng: origin?.pickupLng,
            destinationLat: destination.latitude,
            destinationLng: destination.longitude,
            acceptedCouriers: origin?.acceptedCouriers ?? const [],
            acceptedCourierServices:
                origin?.acceptedCourierServices ?? const [],
          );
      final options = quote.services;

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
        SellerShipping(
          options: options,
          selected: preselected,
          reason: quote.reason,
        ),
      );
      _syncMandatoryInsurance(sellerId);
      _scheduleCouponCatalog();
    } on ApiException catch (e) {
      _setShipping(sellerId, SellerShipping(error: userFacingError(e)));
    }
  }

  void selectCourier(String sellerId, CourierOption option) {
    final current = state.shippingBySeller[sellerId] ?? const SellerShipping();
    _setShipping(sellerId, current.copyWith(selected: option));
    _syncMandatoryInsurance(sellerId);
    _syncChannel();
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
    _syncChannel();
  }

  /// Ports the two `usePayment` effects the picker was missing, and the
  /// default the app never had.
  ///
  /// The channel a buyer picked can stop being valid without them touching
  /// it: QRIS is capped at [qrisMaxIdr], and the total moves when a courier
  /// is chosen, when insurance turns mandatory above Rp500.000, or when a
  /// coupon lands. Web clears the stale channel and settles on the first one
  /// that *is* allowed; the app kept the dead pick and let the buyer submit
  /// with it.
  ///
  /// Until the buyer picks for themselves, this also *chooses* for them —
  /// see [_autoSelectPayment]. After they pick, it only ever repairs a
  /// channel the total has invalidated, and a buyer on Saldo stays there.
  ///
  /// The coupon catalog is priced against the channel, so a channel this
  /// settles on is also what the next catalog fetch is asked about.
  void _syncChannel() {
    _repairChannel();
    _scheduleCouponCatalog();
  }

  void _repairChannel() {
    final total = totals.grandTotalBeforeFee;
    if (total <= 0) return;

    if (!state.paymentTouched) {
      _autoSelectPayment(total);
      return;
    }

    if (state.paymentMethod == PaymentMethod.wallet) return;

    final channel = state.paymentChannel;
    if (channel != null && !isChannelAllowedForAmount(channel, total)) {
      state = state.copyWith(clearChannel: true);
    }
    if (state.paymentChannel != null) return;

    final available = availablePaymentChannels(total);
    if (available.isNotEmpty) {
      state = state.copyWith(paymentChannel: available.first);
    }
  }

  /// Applies [autoSelectPayment], which is where the rule itself lives.
  ///
  /// Only a fee waiver the buyer picked holds them on the gateway. One the
  /// catalog applied by default is worth exactly what saldo already saves,
  /// so it is no reason to keep them off saldo.
  void _autoSelectPayment(int total) {
    final pick = autoSelectPayment(
      grandTotalIdr: total,
      // Unknown reads as nothing to spend, so auto-select never lands on
      // saldo before the balance is in.
      walletBalance: state.walletBalance ?? 0,
      walletAmountDue: totals.walletAmountDue,
      lastPaidChannel: state.lastPaidChannel,
      holdsFeeWaiver: state.couponOverrides.chose(
        CouponSlot.fee,
        itemsSubtotal,
      ),
    );

    if (state.paymentMethod == pick.method &&
        state.paymentChannel == pick.channel) {
      return;
    }
    state = state.copyWith(
      paymentMethod: pick.method,
      paymentChannel: pick.channel,
      clearChannel: pick.channel == null,
    );
  }

  /// Reads what the buyer paid with last time. Failure is silent on purpose:
  /// this only sharpens the default, and a checkout that can't load a
  /// preference is not a checkout that should stop.
  Future<void> loadLastPaidChannel() async {
    // This runs on a microtask that can outlive a checkout the buyer backed
    // out of, so the read itself has to be guarded, not just the write.
    if (_disposed) return;
    final gateway = ref.read(checkoutGatewayProvider);

    try {
      final channel = await gateway.fetchLastPaidChannel();
      if (channel == null || _disposed) return;
      state = state.copyWith(lastPaidChannel: channel);
      _syncChannel();
    } catch (_) {
      // Keep the list's own default.
    }
  }

  void setBuyerNote(String note) => state = state.copyWith(buyerNote: note);

  void selectXendit(PaymentChannel channel) {
    state = state.copyWith(
      paymentMethod: PaymentMethod.xendit,
      paymentChannel: channel,
      paymentTouched: true,
    );
    // Guards a pick made against a total that has since moved.
    _syncChannel();
  }

  /// A fee waiver needs no clearing here: [coupons] drops it for as long as
  /// saldo is the method, and brings it back if the buyer returns to a
  /// gateway channel — the same derivation `useCoupon` does.
  void selectWallet() {
    state = state.copyWith(
      paymentMethod: PaymentMethod.wallet,
      clearChannel: true,
      paymentTouched: true,
    );
    _scheduleCouponCatalog();
  }

  void setWalletBalance(int balance) {
    if (state.walletBalance == balance) return;
    state = state.copyWith(walletBalance: balance);
    // The balance lands after the first build, so the default can only be
    // decided once it has.
    _syncChannel();
  }

  /// Coalesces the courier, channel and insurance changes that each move
  /// the catalog's inputs — `CATALOG_DEBOUNCE_MS` in `useCouponCatalog.ts`.
  Timer? _couponDebounce;
  static const _couponDebounceDelay = Duration(milliseconds: 400);

  /// How long a catalog fetched for the same inputs is reused —
  /// `CATALOG_TTL_MS`.
  static const _couponCatalogTtl = Duration(seconds: 60);

  String? _couponSignature;
  String? _couponRequestedSignature;
  DateTime? _couponFetchedAt;
  int _couponGeneration = 0;

  String get _currentCouponSignature =>
      '$itemsSubtotal|$shippingTotal|${state.paymentChannel?.code ?? '-'}|'
      '${[for (final item in _items) item.cartItemId].join(',')}|'
      '${_loadedDealIds.join(',')}';

  /// Auto-apply needs the catalog before the picker is ever opened, so it
  /// is fetched as soon as the cart and a courier are both settled.
  ///
  /// Inputs already asked about are not asked again — a failed fetch waits
  /// for the buyer to open the picker or retry instead of looping.
  void _scheduleCouponCatalog() {
    if (_disposed) return;
    if (itemsSubtotal <= 0 || shippingTotal <= 0) return;
    if (_currentCouponSignature == _couponRequestedSignature) return;
    _couponDebounce?.cancel();
    _couponDebounce = Timer(_couponDebounceDelay, loadCouponCatalog);
  }

  /// Ports `useCouponCatalog`'s `load`. [force] skips the freshness check,
  /// for a retry or a coupon the server just refused.
  Future<void> loadCouponCatalog({bool force = false}) async {
    if (_disposed) return;
    final signature = _currentCouponSignature;
    final fetchedAt = _couponFetchedAt;
    if (!force &&
        signature == _couponSignature &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _couponCatalogTtl) {
      return;
    }

    _couponRequestedSignature = signature;
    final generation = ++_couponGeneration;
    state = state.copyWith(couponsLoading: true, couponsError: false);
    try {
      final coupons = await ref
          .read(checkoutGatewayProvider)
          .fetchAvailableCoupons(
            shippingTotal: shippingTotal,
            paymentChannel: state.paymentChannel,
            selectedCartItemIds: [for (final item in _items) item.cartItemId],
            dealExternalIds: _loadedDealIds,
          );
      if (_disposed || generation != _couponGeneration) return;
      _couponSignature = signature;
      _couponFetchedAt = DateTime.now();
      state = state.copyWith(couponCatalog: coupons, couponsLoading: false);
    } catch (e) {
      if (_disposed || generation != _couponGeneration) return;
      // A missing promo list costs the discount, not the checkout.
      state = state.copyWith(couponsLoading: false, couponsError: true);
    }
    _syncChannel();
  }

  /// What each coupon slot holds right now — see [resolveCouponSelection].
  CouponSelection get coupons => resolveCouponSelection(
    catalog: state.couponCatalog,
    overrides: state.couponOverrides,
    itemsSubtotal: itemsSubtotal,
    paymentMethod: state.paymentMethod,
    paymentChannel: state.paymentChannel,
    shippingTotal: shippingTotal,
  );

  /// Ports `useCoupon`'s `selectCoupon`.
  void selectCoupon(AvailableCoupon coupon) =>
      _setCouponSlot(coupon.slot, coupon.toApplied());

  /// Ports `clearSlot`: the slot stays empty until the cart changes, rather
  /// than snapping back to the default the buyer just declined.
  void clearCouponSlot(CouponSlot slot) => _setCouponSlot(slot, null);

  /// Ports `invalidateCoupon`: clears the coupon the server named, or every
  /// slot when it named none.
  void invalidateCoupon(int? couponId) {
    final current = coupons;
    final slot = couponId == null
        ? null
        : CouponSlot.values
              .where((s) => current[s]?.couponId == couponId)
              .firstOrNull;
    if (slot != null) {
      _setCouponSlot(slot, null, keepNotice: true);
      return;
    }
    state = state.copyWith(
      couponOverrides: CouponOverrides(
        subtotal: itemsSubtotal,
        slots: const {CouponSlot.shipping: null, CouponSlot.fee: null},
      ),
    );
    _syncChannel();
  }

  void _setCouponSlot(
    CouponSlot slot,
    AppliedCoupon? coupon, {
    bool keepNotice = false,
  }) {
    state = state.copyWith(
      couponOverrides: state.couponOverrides.withSlot(
        slot,
        coupon,
        itemsSubtotal: itemsSubtotal,
      ),
      clearCouponNotice: !keepNotice,
    );
    _syncChannel();
  }

  /// Cart lines plus deals — web's `cardsSubtotal`, the base coupons and
  /// totals are both priced from.
  int get itemsSubtotal =>
      _items.fold(0, (sum, item) => sum + item.subtotal) +
      state.deals.fold(0, (sum, deal) => sum + deal.subtotal);

  int get shippingTotal => state.shippingBySeller.values.fold(
    0,
    (sum, shipping) => sum + (shipping.selected?.cost ?? 0),
  );

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
    coupons: coupons,
  );

  /// Every reason the pay button stays disabled, in the same order the web
  /// evaluates them.
  String? get blockedReason {
    if (isDealCheckout && state.deals.isEmpty) {
      if (state.contextLoading) return 'Memuat penawaran...';
      return state.contextError == null
          ? 'Penawaran ini sudah tidak tersedia.'
          : 'Gagal memuat penawaran.';
    }
    if (_dealIds.isNotEmpty && state.contextLoading) {
      return 'Memuat penawaran...';
    }
    if (_items.isEmpty && state.deals.isEmpty) return 'Keranjang kosong.';
    if (state.address == null) return 'Pilih alamat pengiriman dulu.';
    if (!state.phoneVerified) {
      return 'Verifikasi nomor HP dulu di pengaturan akun.';
    }
    if (state.paymentMethod == PaymentMethod.xendit &&
        state.paymentChannel == null) {
      return 'Pilih metode pembayaran.';
    }
    if (state.paymentMethod == PaymentMethod.wallet) {
      final balance = state.walletBalance;
      // Blocked either way, but only one of these is the buyer's problem.
      if (balance == null) return 'Memuat saldo...';
      if (balance < totals.walletAmountDue) {
        return 'Saldo dompet tidak cukup.';
      }
    }
    for (final sellerId in sellerIds) {
      if (state.shippingBySeller[sellerId]?.selected == null) {
        return 'Pilih kurir untuk semua toko.';
      }
    }
    return null;
  }

  /// Submits and returns where to go next: Xendit's hosted invoice for a
  /// card payment, or null when the wallet settled it outright. Throws
  /// [ApiException] so the page can show the server's own message; a
  /// [CouponInvalidException] also clears the refused coupon first, as
  /// `useCheckoutSubmit` does.
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

      final gateway = ref.read(checkoutGatewayProvider);
      final dealIds = _loadedDealIds;
      final result = isDealCheckout
          ? await gateway.submitDeals(
              dealExternalIds: dealIds,
              courierChoices: choices,
              deliveryAddressSlug: state.address!.slug,
              paymentMethod: state.paymentMethod,
              paymentChannel: state.paymentChannel,
              buyerNote: state.buyerNote,
              couponIds: coupons.ids,
            )
          : dealIds.isNotEmpty
          ? await gateway.submitCartWithDeals(
              selectedCartItemIds: [for (final item in _items) item.cartItemId],
              dealExternalIds: dealIds,
              courierChoices: choices,
              deliveryAddressSlug: state.address!.slug,
              paymentMethod: state.paymentMethod,
              paymentChannel: state.paymentChannel,
              buyerNote: state.buyerNote,
              couponIds: coupons.ids,
            )
          : await gateway.submit(
              courierChoices: choices,
              deliveryAddressSlug: state.address!.slug,
              paymentMethod: state.paymentMethod,
              paymentChannel: state.paymentChannel,
              buyerNote: state.buyerNote,
              couponIds: coupons.ids,
              selectedCartItemIds: [for (final item in _items) item.cartItemId],
            );

      // A saldo checkout is already settled server-side when this returns:
      // `pay_checkout_with_wallet` debited the balance through `credit_wallet`
      // and wrote the ledger row before responding. All three of these are
      // plain FutureProviders that stay cached for the session, so without
      // this the buyer reached Pesanan with the pre-checkout saldo, nothing
      // in Riwayat, and an order list missing what they had just bought —
      // the wallet page's pull-to-refresh was the only thing that cleared
      // them. A card payment is still pending at this point and revalidates
      // when its webhook lands, so it is deliberately left alone.
      if (state.paymentMethod == PaymentMethod.wallet) {
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(walletActivityProvider);
        ref.invalidate(ordersProvider);
      }
      return result;
    } on CouponInvalidException catch (e) {
      if (!_disposed) {
        state = state.copyWith(couponNotice: e.message);
        invalidateCoupon(e.couponId);
        unawaited(loadCouponCatalog(force: true));
      }
      rethrow;
    } finally {
      if (!_disposed) state = state.copyWith(submitting: false);
    }
  }

  Future<void> _refreshAllRates() async {
    if (_disposed || state.address == null) return;
    await Future.wait([
      for (final sellerId in sellerIds) fetchRatesForSeller(sellerId),
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

/// Auto-disposed on purpose: checkout is a page, not a session.
///
/// A kept-alive notifier survived leaving the page, so a second checkout
/// reused the first one's state — and because `selectAddress` early-returns
/// when the address hasn't changed, nothing ever asked for quotes against
/// the new cart. `shippingBySeller` still held the previous seller's entry
/// and had none for this one, which the picker renders as "0 layanan
/// tersedia". Entering the page now always starts from a clean state and
/// re-quotes every seller in it.
final checkoutProvider =
    NotifierProvider.autoDispose<CheckoutNotifier, CheckoutState>(
      CheckoutNotifier.new,
      dependencies: [
        checkoutDealIdsProvider,
        checkoutWithCartSelectionProvider,
      ],
    );
