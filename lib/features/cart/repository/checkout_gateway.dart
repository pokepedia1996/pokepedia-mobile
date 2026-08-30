import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/supabase_provider.dart';
import 'models/checkout_models.dart';

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

  /// `cancelled | expired | refunded | failed | refund_required` — the
  /// `CancelledCheckoutStatus` union in `lib/cart/shared.ts`.
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

/// The three checkout steps that cannot run in the app.
///
/// Everything else — cart review, address, insurance rules, coupons, the fee
/// and total arithmetic, payment-channel eligibility — is local and lives in
/// `CheckoutNotifier`. What's left here needs either a secret
/// (`BITESHIP_API_KEY`, `XENDIT_SECRET_KEY`) or `service_role`, so it stays
/// behind the server and the app authenticates with its Supabase session.
class CheckoutGateway {
  CheckoutGateway(this._api, this._client);

  final PokepediaApi _api;
  final SupabaseClient _client;

  /// Whether the buyer has a verified phone.
  ///
  /// Reads `profiles_private` directly: its "Self can read own private
  /// profile" policy is `auth.uid() = id`, so this needs no server route.
  /// The pickup origins this used to fetch alongside it are gone — the
  /// `shipping-rates` function resolves them itself now, which is the only
  /// place they were ever used.
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
      throw ApiException(e.message);
    }
  }

  /// Courier quotes for one seller's parcel.
  ///
  /// Calls the `shipping-rates` Edge Function rather than
  /// `/api/shipping/rates`. Two reasons: the Biteship key has to stay
  /// server-side, and pokepedia.id sits behind Vercel's Attack Challenge
  /// Mode, which answers any non-browser client with a JS challenge. Supabase
  /// Functions are not behind it.
  ///
  /// It takes the seller and the buyer's own address rather than an origin:
  /// `seller_profiles` is self-only under RLS, so the app cannot read a
  /// pickup point to send. The function resolves both ends itself.
  Future<List<CourierOption>> fetchRates({
    required String sellerId,
    required String addressSlug,
    required int quantity,
    required int itemValue,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'shipping-rates',
        body: {
          'sellerId': sellerId,
          'addressSlug': addressSlug,
          'quantity': quantity,
          'itemValue': itemValue,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw const ApiException('Respons tarif tidak dikenali.');
      }
      if (response.status >= 400) {
        throw ApiException(
          data['error'] as String? ?? 'Gagal mengambil tarif kurir',
          statusCode: response.status,
        );
      }

      final services = data['services'];
      if (services is! List) return const [];
      return services
          .whereType<Map<String, dynamic>>()
          .map(_courierFromJson)
          .toList();
    } on FunctionException catch (e) {
      // The function's own JSON error, when it answered with one.
      final details = e.details;
      if (details is! Map) {
        // Not our JSON — the function never answered, or something between
        // the client and it did. Carry the raw body: every error this
        // function itself returns is JSON, so a non-JSON body identifies
        // the responder, and without it the status alone is unactionable.
        final raw = details?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        final snippet = raw == null || raw.isEmpty
            ? 'tanpa isi'
            : (raw.length > 160 ? '${raw.substring(0, 160)}…' : raw);
        throw ApiException(
          'Tarif kurir gagal (${e.status}): $snippet',
          statusCode: e.status,
        );
      }
      final message =
          details['error'] as String? ?? 'Gagal mengambil tarif kurir';
      final detail = details['detail'] as String?;
      throw ApiException(
        detail == null ? message : '$message — $detail',
        statusCode: e.status,
      );
    }
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
    String? couponCode,
    List<int> selectedCartItemIds = const [],
  }) async {
    final json = await _api.post('/api/cart/checkout', {
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
      if (couponCode != null) 'couponCode': couponCode,
      if (selectedCartItemIds.isNotEmpty)
        'selectedCartItemIds': selectedCartItemIds,
    });

    final dropped = json['droppedItems'];
    print('WKWKWK ${json.toString()}');
    return CheckoutResult(
      invoiceUrl: json['invoiceUrl'] as String?,
      redirect: json['redirect'] as String?,
      externalId: json['externalId'] as String?,
      totalAmount: (json['totalAmount'] as num?)?.round(),
      droppedItems: dropped is List
          ? dropped.map((e) => e.toString()).toList()
          : const [],
    );
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
  /// Success is keyed off `paid_at` rather than a status spelling — the
  /// webhook stamps it, and the cancelled vocabulary is the part that's
  /// enumerated.
  Future<CheckoutProgress> fetchProgress(String externalId) async {
    const cancelled = {
      'cancelled',
      'expired',
      'refunded',
      'failed',
      'refund_required',
    };

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

    final raw = row['status'] as String? ?? 'pending';
    if (row['paid_at'] != null) {
      return CheckoutProgress(status: CheckoutStatus.paid, raw: raw);
    }
    if (cancelled.contains(raw)) {
      return CheckoutProgress(status: CheckoutStatus.cancelled, raw: raw);
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
