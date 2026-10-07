import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../expansions/repository/models/store_identity.dart';
import 'cart_repository.dart';
import 'models/checkout_deal.dart';
import 'models/checkout_models.dart';
import '../../../core/errors/user_message.dart';

/// What checkout needs to know about the buyer before it can start.
class CheckoutContext {
  const CheckoutContext({required this.phoneVerified});

  /// `/api/cart/checkout` refuses an unverified buyer outright, so the
  /// button is gated on this rather than letting the submit fail.
  final bool phoneVerified;
}

/// What a submitted checkout produced — the full envelope
/// `POST /api/cart/checkout` returns.
///
/// A card payment ends on Xendit's hosted invoice page, the one screen that
/// is deliberately not native since it's the gateway's own PCI surface.
/// A wallet payment settles server-side and comes back as a redirect path.
class CheckoutResult {
  const CheckoutResult({
    this.invoiceUrl,
    this.redirect,
    this.externalId,
    this.totalAmount,
    this.droppedItems = const [],
  });

  final String? invoiceUrl;
  final String? redirect;

  /// `INV-260810-A7K3P-…`, minted by us and echoed back on Xendit's webhook.
  /// This is what the buyer's `carts` row is keyed by, so it's what the app
  /// polls with once the payment page closes.
  final String? externalId;

  final int? totalAmount;

  /// Lines the server refused at lock time — sold out underneath the buyer,
  /// price moved, seller went on vacation. The order went ahead without
  /// them, so the buyer has to be told rather than silently shortchanged.
  /// One Indonesian sentence per line; see [parseDroppedItems].
  final List<String> droppedItems;

  /// Named fields rather than the default `Instance of 'CheckoutResult'`:
  /// which of these came back is exactly what decides where checkout goes
  /// next, so a log line that omits them says nothing.
  @override
  String toString() =>
      'CheckoutResult(externalId: $externalId, invoiceUrl: $invoiceUrl, '
      'redirect: $redirect, totalAmount: $totalAmount, '
      'droppedItems: ${droppedItems.length})';
}

/// Where a checkout stands. Read from the buyer's own `carts` row.
enum CheckoutStatus {
  /// Invoice open, nothing settled yet.
  pending,

  /// The webhook settled it. This is the only success.
  paid,

  /// Every terminal `carts.status` other than `paid` — see
  /// [CheckoutGateway.terminalUnpaidStatuses].
  cancelled,
}

/// A checkout's state, as the buyer can see it.
class CheckoutProgress {
  const CheckoutProgress({required this.status, required this.raw});

  final CheckoutStatus status;

  /// The literal `carts.status`, kept for the cancelled reasons the enum
  /// collapses together.
  final String raw;

  bool get isSettled => status != CheckoutStatus.pending;
}

/// A checkout's QRIS code, as the gateway reports it.
class QrisCharge {
  const QrisCharge({
    required this.qrString,
    required this.amount,
    this.expiresAt,
    this.paidAt,
  });

  /// Null once the checkout is already paid — there's nothing left to scan.
  final String? qrString;
  final int amount;
  final DateTime? expiresAt;
  final DateTime? paidAt;

  bool get isPaid => paidAt != null;
}

/// The QR couldn't be produced. Carries the hosted invoice, which can still
/// take the payment, so the caller has somewhere to send the buyer.
class QrisUnavailableException extends ApiException {
  const QrisUnavailableException({
    required String message,
    this.invoiceUrl,
    this.diagnostic,
  }) : super(message);

  final String? invoiceUrl;

  /// What the invoice held when no QR could be read off it. Shown in the
  /// error state, because "QRIS belum tersedia" on its own can't be told
  /// apart from a misparse or an invoice that never got a channel.
  final String? diagnostic;
}

/// `/api/cart/checkout` refused because the buyer already has an unpaid
/// invoice open (`409 pending_invoice`). Carries that invoice so the buyer
/// can finish it instead of being stuck behind it.
class PendingInvoiceException extends ApiException {
  const PendingInvoiceException({
    required String message,
    required this.externalId,
    required this.invoiceUrl,
    this.totalAmount,
  }) : super(message, statusCode: 409, code: 'pending_invoice');

  final String? externalId;
  final String? invoiceUrl;
  final int? totalAmount;
}

/// `/api/cart/checkout` refused a coupon at lock time (`400 coupon_invalid`).
/// [couponId] names the offender; null means the server could not say, and
/// every coupon should be cleared — `invalidateCoupon` in `useCoupon.ts`.
class CouponInvalidException extends ApiException {
  const CouponInvalidException({required String message, this.couponId})
    : super(message, statusCode: 400, code: 'coupon_invalid');

  final int? couponId;
}

/// Turns the route's `droppedItems` (`[{reason, available}]`) into one
/// sentence per line, with the same copy the pre-submit cart check uses.
List<String> parseDroppedItems(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        cartLineProblemMessage(
          item['reason'] as String?,
          available: (item['available'] as num?)?.toInt(),
        )
      else if (item is String)
        cartLineProblemMessage(item),
  ];
}

/// The checkout steps that cannot run in the app.
///
/// Everything else — cart review, address, insurance rules, coupons, the fee
/// and total arithmetic, payment-channel eligibility — is local and lives in
/// `CheckoutNotifier`. What's left here needs either a secret
/// (`BITESHIP_API_KEY`, `XENDIT_SECRET_KEY`) or `service_role`, so it stays
/// behind the server and the app authenticates with its Supabase session.
///
/// Those calls go to pokepedia.id's own `/api` routes, which read the
/// session off `Authorization: Bearer` and answer the app exactly as they
/// answer the web. The one exception left is the QRIS payload, which has no
/// route on the web app and is still served by an Edge Function.
class CheckoutGateway {
  CheckoutGateway(this._api, this._client);

  final PokepediaApi _api;
  final SupabaseClient _client;

  /// Whether the buyer has a verified phone.
  ///
  /// Reads `profiles_private` directly: its "Self can read own private
  /// profile" policy is `auth.uid() = id`, so this needs no server route.
  /// `GET /api/cart` reports the same flag alongside the pickup origins, but
  /// it costs a round trip to the edge; this one answers from Postgres.
  Future<CheckoutContext> fetchContext() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const CheckoutContext(phoneVerified: false);
    try {
      final row = await _client
          .from('profiles_private')
          .select('phone_verified_at')
          .eq('id', userId)
          .maybeSingle();
      return CheckoutContext(phoneVerified: row?['phone_verified_at'] != null);
    } on PostgrestException catch (e) {
      throw ApiException(userFacingError(e));
    }
  }

  /// Where each seller in the cart ships from, keyed by seller id.
  ///
  /// From `GET /api/cart` rather than Postgres: every `seller_profiles`
  /// policy is `auth.uid() = user_id`, so a buyer reading a seller's pickup
  /// point gets an empty list. That route resolves it with a service client,
  /// exactly as web's checkout does before it quotes anything.
  Future<Map<String, SellerOrigin>> fetchSellerOrigins() async {
    final json = await _api.get('/api/cart');
    final origins = json['sellerOrigins'];
    if (origins is! Map) return const {};
    return {
      for (final entry in origins.entries)
        if (entry.value is Map)
          entry.key.toString(): SellerOrigin.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          ),
    };
  }

  /// Courier quotes for one seller's parcel — `POST /api/shipping/rates`,
  /// the same route and the same body web's checkout sends.
  ///
  /// This used to go through a `shipping-rates` Edge Function, because
  /// pokepedia.id answered non-browser clients with Vercel's JS challenge.
  /// [PokepediaApi] carries the firewall's bypass header and the session's
  /// bearer token now, and every `/api` route authenticates from that token,
  /// so the detour — and the second copy of the pricing logic that came with
  /// it — is no longer needed.
  Future<List<CourierOption>> fetchRates({
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
    final quote = await fetchRateQuote(
      originCityId: originCityId,
      destinationCityId: destinationCityId,
      quantity: quantity,
      itemValue: itemValue,
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      acceptedCouriers: acceptedCouriers,
      acceptedCourierServices: acceptedCourierServices,
    );
    return quote.services;
  }

  /// [fetchRates] with the route's `reason` kept — `fetchShippingRates` in
  /// `rates.repository.ts`, which the courier section needs to say whether an
  /// empty list is the route, the seller's whitelist, or an outage.
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
    final json = await _api.post('/api/shipping/rates', {
      'originCityId': originCityId,
      'destinationCityId': destinationCityId,
      'weight': kShippingWeightPerUnitGrams * (quantity < 1 ? 1 : quantity),
      if (itemValue > 0) 'itemValue': itemValue,
      // Only quote the premium when there is a value to insure, which is
      // also what keeps the route from serving this quote out of its cache.
      'includeInsurance': itemValue > 0,
      if (originLat != null) 'originLat': originLat,
      if (originLng != null) 'originLng': originLng,
      if (destinationLat != null) 'destinationLat': destinationLat,
      if (destinationLng != null) 'destinationLng': destinationLng,
      'acceptedCouriers': acceptedCouriers,
      'acceptedCourierServices': acceptedCourierServices,
    });
    return parseRateQuote(json);
  }

  /// Reads a `/api/shipping/rates` body.
  static RateQuote parseRateQuote(Map<String, dynamic> json) {
    final services = json['services'];
    return RateQuote(
      services: services is List
          ? services
                .whereType<Map<String, dynamic>>()
                .map(_courierFromJson)
                .toList()
          : const [],
      reason: RatesReason.fromWire(json['reason']),
    );
  }

  /// Ports `submitCartCheckout`. The server validates and locks the cart,
  /// books the shipping fees, redeems the coupon and opens the invoice in
  /// one transaction — none of which the app can do itself, and none of
  /// which should be duplicated in two places.
  Future<CheckoutResult> submit({
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    List<int> couponIds = const [],
    List<int> selectedCartItemIds = const [],
  }) async {
    final json = await _postCheckout(
      checkoutRequestBody(
        courierChoices: courierChoices,
        deliveryAddressSlug: deliveryAddressSlug,
        paymentMethod: paymentMethod,
        paymentChannel: paymentChannel,
        buyerNote: buyerNote,
        couponIds: couponIds,
        selectedCartItemIds: selectedCartItemIds.isEmpty
            ? null
            : selectedCartItemIds,
      ),
    );
    return _resultFrom(json);
  }

  /// Pays accepted bid proposals and nothing else from the cart.
  ///
  /// `selectedCartItemIds` goes out as an explicit empty list: the route
  /// reads an *absent* selection as "the whole cart", so leaving it off — as
  /// [submit] does for an empty one — invoiced the buyer for every unticked
  /// cart line on top of the deal (web's e6bfd54d).
  Future<CheckoutResult> submitDeals({
    required List<String> dealExternalIds,
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    List<int> couponIds = const [],
  }) async {
    final json = await _postCheckout(
      checkoutRequestBody(
        courierChoices: courierChoices,
        deliveryAddressSlug: deliveryAddressSlug,
        paymentMethod: paymentMethod,
        paymentChannel: paymentChannel,
        buyerNote: buyerNote,
        couponIds: couponIds,
        selectedCartItemIds: const [],
        selectedDealExternalIds: dealExternalIds,
      ),
    );
    return _resultFrom(json);
  }

  /// The `CheckoutBodySchema` body. A null [selectedCartItemIds] is left off
  /// (the whole cart); an empty one is sent, meaning no cart lines at all.
  static Map<String, dynamic> checkoutRequestBody({
    required List<CourierChoice> courierChoices,
    required String deliveryAddressSlug,
    required PaymentMethod paymentMethod,
    PaymentChannel? paymentChannel,
    String buyerNote = '',
    List<int> couponIds = const [],
    List<int>? selectedCartItemIds,
    List<String> selectedDealExternalIds = const [],
  }) => {
    'courierChoices': [
      for (final choice in courierChoices)
        {
          'sellerId': choice.sellerId,
          'courier': choice.courier,
          'service': choice.service,
          'insuranceEnabled': choice.insuranceEnabled,
        },
    ],
    'deliveryAddressSlug': deliveryAddressSlug,
    'paymentMethod': paymentMethod == PaymentMethod.wallet
        ? 'wallet'
        : 'xendit',
    if (paymentMethod == PaymentMethod.xendit && paymentChannel != null)
      'paymentChannel': paymentChannel.code,
    if (buyerNote.trim().isNotEmpty) 'buyerNote': buyerNote.trim(),
    if (couponIds.isNotEmpty) 'couponIds': couponIds,
    if (selectedCartItemIds != null) 'selectedCartItemIds': selectedCartItemIds,
    if (selectedDealExternalIds.isNotEmpty)
      'selectedDealExternalIds': selectedDealExternalIds,
  };

  static CheckoutResult _resultFrom(Map<String, dynamic> json) =>
      CheckoutResult(
        invoiceUrl: json['invoiceUrl'] as String?,
        redirect: json['redirect'] as String?,
        externalId: json['externalId'] as String?,
        totalAmount: (json['totalAmount'] as num?)?.round(),
        droppedItems: parseDroppedItems(json['droppedItems']),
      );

  /// Raises the two refusals checkout acts on as their own types; every
  /// other failure stays a plain [ApiException] carrying the server's text.
  Future<Map<String, dynamic>> _postCheckout(Map<String, dynamic> body) async {
    try {
      return await _api.post('/api/cart/checkout', body);
    } on ApiException catch (e) {
      final payload = e.payload;
      if (e.code == 'pending_invoice') {
        final pending = payload?['pendingInvoice'];
        final invoice = pending is Map ? pending : const {};
        throw PendingInvoiceException(
          message: e.message,
          externalId: invoice['externalId'] as String?,
          invoiceUrl: invoice['invoiceUrl'] as String?,
          totalAmount: (invoice['totalAmount'] as num?)?.round(),
        );
      }
      if (e.code == 'coupon_invalid') {
        throw CouponInvalidException(
          message: e.message,
          couponId: (payload?['couponId'] as num?)?.toInt(),
        );
      }
      rethrow;
    }
  }

  /// The buyer's coupons for this checkout, eligible or not — the same
  /// `POST /api/coupons/available` web's `fetchAvailableCoupons` calls.
  ///
  /// Through the route rather than `list_available_coupons` directly: the
  /// route prices the items subtotal itself from [selectedCartItemIds] and
  /// the snapshots of [dealExternalIds], so eligibility is never judged
  /// against a number the client supplied.
  Future<List<AvailableCoupon>> fetchAvailableCoupons({
    required int shippingTotal,
    required PaymentChannel? paymentChannel,
    required List<int> selectedCartItemIds,
    List<String> dealExternalIds = const [],
  }) async {
    final json = await _api.post('/api/coupons/available', {
      'shippingTotal': shippingTotal,
      'paymentChannel': paymentChannel?.code,
      'selectedCartItemIds': selectedCartItemIds,
      if (dealExternalIds.isNotEmpty) 'dealExternalIds': dealExternalIds,
    });
    final rows = json['coupons'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (AvailableCoupon.tryParse(row) case final coupon?) coupon,
    ];
  }

  /// The buyer's accepted bid proposals still waiting for checkout, newest
  /// first — or just [externalIds], when given.
  ///
  /// The same filter `/api/cart/checkout` applies before it will combine a
  /// deal (`kind = 'bid'`, `pending`, no invoice yet), read straight off
  /// `carts` under `carts_select_own`. Expired rows are left out because the
  /// route's lock would refuse them anyway.
  Future<List<CheckoutDeal>> fetchDeals({List<String>? externalIds}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    if (externalIds != null && externalIds.isEmpty) return const [];

    var query = _client
        .from('carts')
        .select('external_id, expires_at, created_at, cart_snapshot')
        .eq('user_id', userId)
        .eq('kind', 'bid')
        .eq('status', 'pending')
        .isFilter('invoice_url', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());
    if (externalIds != null) query = query.inFilter('external_id', externalIds);

    final List<dynamic> rows;
    try {
      rows = await query.order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      throw ApiException(userFacingError(e));
    }

    final deals = [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (CheckoutDeal.fromCartRow(row) case final deal?) deal,
    ];
    final stores = await fetchStoreIdentities(
      _client,
      deals.map((deal) => deal.sellerId),
    );
    return [
      for (final deal in deals)
        deal.withStore(
          storeName: stores[deal.sellerId]?.storeName,
          storeLogoUrl: stores[deal.sellerId]?.storeLogoUrl,
        ),
    ];
  }

  /// The QRIS payload for a checkout, so the app can draw the code itself
  /// rather than hand the buyer to Xendit's hosted page.
  ///
  /// Reads the QR off the invoice `/api/cart/checkout` already opened — the
  /// invoice webhook is the only settlement path this project implements, so
  /// a code charged through any other channel would be money taken against
  /// an order nothing marks paid. When the invoice exposes no QR the
  /// function says so, and [QrisCharge.invoiceUrl] is the way to finish.
  Future<QrisCharge> fetchQris(String externalId) async {
    final response = await _client.functions.invoke(
      'qris-payment',
      body: {'externalId': externalId},
    );

    final data = response.data;
    if (data is! Map) {
      throw const ApiException('Respons pembayaran tidak dikenali.');
    }
    if (response.status >= 400) {
      throw QrisUnavailableException(
        message: switch (data['error']) {
          'qr_unavailable' => 'QRIS belum tersedia untuk pesanan ini.',
          'invoice_missing' => 'Tagihan pembayaran belum dibuat.',
          'gateway_unreachable' => 'Gateway pembayaran tidak merespons.',
          'checkout_not_found' => 'Pesanan tidak ditemukan.',
          _ => 'Gagal memuat QRIS.',
        },
        invoiceUrl: data['invoiceUrl'] as String?,
        // What the invoice actually carried. Four different causes collapse
        // into one message otherwise, and they need different fixes.
        diagnostic: data['diagnostic']?.toString(),
      );
    }

    return QrisCharge(
      qrString: data['qrString'] as String?,
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(
        data['expiresAt'] as String? ?? '',
      )?.toLocal(),
      paidAt: DateTime.tryParse(data['paidAt'] as String? ?? '')?.toLocal(),
    );
  }

  /// Where the checkout [externalId] stands.
  ///
  /// Reads `carts` directly rather than `GET /api/settlements/[slug]/status`:
  /// `carts_select_own` is `user_id = auth.uid()`, so the buyer can read
  /// their own row, and that keeps the one query that decides "did my money
  /// arrive" off an endpoint the edge currently challenges.
  ///
  /// The gateway channel the buyer last actually paid with, or null if they
  /// have never paid, paid from saldo, or the row isn't readable.
  ///
  /// `carts.payment_channel` is stamped by `/api/cart/checkout` with the
  /// uppercase channel code, or the literal "WALLET" for a saldo payment —
  /// which maps to null here, since saldo is a [PaymentMethod], not a
  /// channel. Keyed off `paid_at` for the same reason [fetchProgress] is:
  /// an abandoned cart carries the channel the buyer *chose*, and that is
  /// not evidence of what they use.
  Future<PaymentChannel?> fetchLastPaidChannel() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('carts')
        .select('payment_channel')
        .eq('user_id', userId)
        .not('paid_at', 'is', null)
        .order('paid_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final code = (row?['payment_channel'] as String?)?.toUpperCase();
    if (code == null || code == 'WALLET') return null;
    for (final channel in PaymentChannel.values) {
      if (channel.code == code) return channel;
    }
    return null;
  }

  /// Every `carts.status` the `carts_status_check` constraint allows that
  /// ends a checkout without an order: web's `CancelledCheckoutStatus` plus
  /// the refund-bound states `commit_cart_match` narrows a paid-but-
  /// unfulfillable cart to (`REFUNDABLE_CART_STATUSES`) and `refund_failed`.
  static const terminalUnpaidStatuses = {
    'cancelled',
    'expired',
    'refunded',
    'failed',
    'refund_required',
    'failed_unavailable',
    'failed_buyer_ineligible',
    'refund_failed',
  };

  /// Success is keyed off `paid_at` rather than a status spelling — the
  /// webhook stamps it — except for the terminal states, which are checked
  /// first: a cart that was paid and then failed or refunded keeps its
  /// `paid_at`, and calling that "paid" would promise an order that never
  /// came to exist.
  Future<CheckoutProgress> fetchProgress(String externalId) async {
    final row = await _client
        .from('carts')
        .select('status, paid_at')
        .eq('external_id', externalId)
        .maybeSingle();

    // A row the buyer can't see is not a paid one; keep waiting rather than
    // claiming either outcome.
    if (row == null) {
      return const CheckoutProgress(
        status: CheckoutStatus.pending,
        raw: 'pending',
      );
    }

    return progressFromRow(
      status: row['status'] as String?,
      paidAt: row['paid_at'],
    );
  }

  /// The decision [fetchProgress] makes from one `carts` row.
  static CheckoutProgress progressFromRow({
    required String? status,
    required Object? paidAt,
  }) {
    final raw = status ?? 'pending';
    if (terminalUnpaidStatuses.contains(raw)) {
      return CheckoutProgress(status: CheckoutStatus.cancelled, raw: raw);
    }
    if (paidAt != null) {
      return CheckoutProgress(status: CheckoutStatus.paid, raw: raw);
    }
    return CheckoutProgress(status: CheckoutStatus.pending, raw: raw);
  }

  static CourierOption _courierFromJson(Map<String, dynamic> json) {
    return CourierOption(
      courier: json['courier'] as String? ?? '',
      courierName: json['courierName'] as String? ?? '',
      service: json['service'] as String? ?? '',
      description: json['description'] as String? ?? '',
      cost: (json['cost'] as num?)?.round() ?? 0,
      durationRange: json['durationRange'] as String? ?? '',
      durationUnit: json['durationUnit'] as String? ?? '',
      insuranceAvailable: json['insuranceAvailable'] as bool? ?? false,
      insuranceFee: (json['insuranceFee'] as num?)?.round() ?? 0,
    );
  }
}

/// One seller's shipping decision, as `/api/cart/checkout` expects it.
class CourierChoice {
  const CourierChoice({
    required this.sellerId,
    required this.courier,
    required this.service,
    required this.insuranceEnabled,
  });

  final String sellerId;
  final String courier;
  final String service;
  final bool insuranceEnabled;
}

final checkoutGatewayProvider = Provider(
  (ref) => CheckoutGateway(
    ref.read(pokepediaApiProvider),
    ref.read(supabaseClientProvider),
  ),
);
