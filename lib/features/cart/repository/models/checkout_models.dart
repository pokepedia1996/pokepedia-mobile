import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bucket used to group [CourierOption]s in the courier picker sheet.
/// Ports `CourierBucket` from `lib/cart/shared.ts`.
enum CourierBucket { instant, sameDay, overnight, regular }

class CourierBucketMeta {
  const CourierBucketMeta({
    required this.bucket,
    required this.title,
    required this.caption,
    required this.icon,
  });

  final CourierBucket bucket;
  final String title;
  final String caption;
  final IconData icon;
}

const courierBucketMetas = [
  CourierBucketMeta(
    bucket: CourierBucket.instant,
    title: 'Pengiriman Instan',
    caption: '1-3 jam',
    icon: LucideIcons.zap,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.sameDay,
    title: 'Same Day',
    caption: '6-12 jam',
    icon: LucideIcons.zap,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.overnight,
    title: 'Overnight',
    caption: 'Besok sampai',
    icon: LucideIcons.truck,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.regular,
    title: 'Reguler',
    caption: '2-5 hari',
    icon: LucideIcons.truck,
  ),
];

/// Mirrors `categorizeByDuration` from `lib/cart/shared.ts`.
CourierBucket categorizeByDuration({
  required String durationRange,
  required String durationUnit,
}) {
  final unit = durationUnit.toLowerCase();
  final matches = RegExp(r'\d+(?:\.\d+)?').allMatches(durationRange).toList();
  final max = matches.isEmpty ? null : double.tryParse(matches.last.group(0)!);

  if (unit.startsWith('hour')) {
    if (max != null && max <= 3) return CourierBucket.instant;
    return CourierBucket.sameDay;
  }
  if (unit.startsWith('day')) {
    if (max != null && max <= 1) return CourierBucket.overnight;
    return CourierBucket.regular;
  }
  return CourierBucket.regular;
}

/// A single shipping service quote for a seller. Ports `CourierOption` from
/// `features/checkout/types.ts`.
class CourierOption {
  const CourierOption({
    required this.courier,
    required this.courierName,
    required this.service,
    required this.description,
    required this.cost,
    required this.durationRange,
    required this.durationUnit,
    this.insuranceAvailable = false,
    this.insuranceFee = 0,
  });

  final String courier;
  final String courierName;
  final String service;
  final String description;
  final int cost;
  final String durationRange;
  final String durationUnit;
  final bool insuranceAvailable;
  final int insuranceFee;

  CourierBucket get bucket => categorizeByDuration(
    durationRange: durationRange,
    durationUnit: durationUnit,
  );

  String get etaLabel {
    final unit = durationUnit.toLowerCase();
    if (unit.startsWith('hour')) return '$durationRange jam';
    if (unit.startsWith('day')) return '$durationRange hari';
    return durationRange;
  }

  String get optionKey => '$courier-$service';
}

/// Why `/api/shipping/rates` offered fewer couriers than exist on the route.
/// Ports `RatesReason` and `resolveRatesReason` from `features/checkout`.
enum RatesReason {
  /// Biteship quoted nothing at all for this origin and destination.
  noCoverage,

  /// Biteship quoted the route, but none of it is a courier the seller accepts.
  sellerRestricted,

  /// Some quotes survived the seller's courier whitelist, but not all.
  sellerRestrictedPartial;

  /// Unknown or absent values read as null, as `RATES_REASONS.find` does.
  static RatesReason? fromWire(Object? raw) => switch (raw) {
    'no_coverage' => RatesReason.noCoverage,
    'seller_restricted' => RatesReason.sellerRestricted,
    'seller_restricted_partial' => RatesReason.sellerRestrictedPartial,
    _ => null,
  };
}

/// What the courier section says when a quote came back empty —
/// `EMPTY_COURIER_MESSAGES` in `seller-group-card.tsx`, where a missing
/// reason is its `unavailable` entry.
String emptyCourierMessage(RatesReason? reason) => switch (reason) {
  RatesReason.noCoverage => 'Penjual ini tidak melayani pengiriman ke alamatmu',
  RatesReason.sellerRestricted || RatesReason.sellerRestrictedPartial =>
    'Penjual ini tidak menerima kurir yang melayani rute ke alamatmu',
  null => 'Layanan kurir sedang gangguan',
};

/// The hint web shows above a courier list the seller's whitelist trimmed.
const partialCourierListHint =
    'Penjual ini hanya menerima sebagian kurir, jadi pilihannya lebih '
    'sedikit dari biasanya.';

/// One `POST /api/shipping/rates` answer: the quotes plus, when the list is
/// short or empty, the reason it is.
class RateQuote {
  const RateQuote({this.services = const [], this.reason});

  final List<CourierOption> services;
  final RatesReason? reason;
}

/// Where a seller's parcels leave from, and which couriers they accept —
/// one entry of `GET /api/cart`'s `sellerOrigins`.
///
/// It has to come from the server: every `seller_profiles` policy is
/// `auth.uid() = user_id`, so a buyer selecting the seller's pickup point
/// gets nothing back. That route reads it with a service client on the
/// buyer's behalf, which is the same thing web's checkout does.
class SellerOrigin {
  const SellerOrigin({
    this.cityId,
    this.cityName,
    this.pickupLat,
    this.pickupLng,
    this.acceptedCouriers = const [],
    this.acceptedCourierServices = const [],
    this.isActive = false,
  });

  factory SellerOrigin.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        raw is List ? raw.whereType<String>().toList() : const <String>[];
    return SellerOrigin(
      cityId: json['cityId'] as String?,
      cityName: json['cityName'] as String?,
      pickupLat: (json['pickupLat'] as num?)?.toDouble(),
      pickupLng: (json['pickupLng'] as num?)?.toDouble(),
      acceptedCouriers: strings(json['acceptedCouriers']),
      acceptedCourierServices: strings(json['acceptedCourierServices']),
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  /// The BPS city code Biteship prices against ("31.71"). Null for a seller
  /// who has not finished setting their store's address up — nothing can be
  /// quoted from them until they do.
  final String? cityId;
  final String? cityName;
  final double? pickupLat;
  final double? pickupLng;
  final List<String> acceptedCouriers;
  final List<String> acceptedCourierServices;
  final bool isActive;
}

/// `SHIPPING_WEIGHT_PER_UNIT_GRAMS` in `lib/shipping/core/constants.ts` —
/// what one card is quoted as weighing.
const kShippingWeightPerUnitGrams = 10;

/// A saved shipping destination. Ports the relevant subset of `Address`
/// from `lib/location/addresses.ts`.
class CheckoutAddress {
  const CheckoutAddress({
    required this.id,
    required this.label,
    required this.contactName,
    required this.contactPhone,
    required this.fullAddress,
    required this.district,
    required this.cityName,
    required this.provinceName,
    required this.postalCode,
    this.isPrimary = false,
  });

  final int id;
  final String label;
  final String contactName;
  final String contactPhone;
  final String fullAddress;
  final String district;
  final String cityName;
  final String provinceName;
  final String postalCode;
  final bool isPrimary;
}

/// Ports `PaymentChannel` / `PaymentChannelMeta` from
/// `features/checkout/domain/payment-channels.ts`. Which of these a checkout
/// may use is the server's call — see [PaymentOptions].
enum PaymentChannel {
  qris,
  bca,
  bri,
  mandiri,
  bni,
  permata,
  danamon,
  cimb,
  btn,
  doku,
  maybank,
  bnc,
  bss,
  bjb,
  sinarmas,
}

extension PaymentChannelX on PaymentChannel {
  /// The wire value `/api/cart/checkout` expects: `PAYMENT_CHANNEL_CODES`.
  String get code => name.toUpperCase();

  /// The channel for a wire [code]; null for one this version doesn't know.
  static PaymentChannel? fromCode(String? code) {
    final upper = code?.toUpperCase();
    for (final channel in PaymentChannel.values) {
      if (channel.code == upper) return channel;
    }
    return null;
  }
}

enum PaymentChannelGroup { qr, va }

class PaymentChannelMeta {
  const PaymentChannelMeta({
    required this.channel,
    required this.group,
    required this.label,
    required this.description,
  });

  const PaymentChannelMeta.va(this.channel, String bank, [String? fullName])
    : group = PaymentChannelGroup.va,
      label = '$bank Virtual Account',
      description = 'Transfer ke nomor VA ${fullName ?? bank}';

  final PaymentChannel channel;
  final PaymentChannelGroup group;
  final String label;
  final String description;
}

const paymentChannels = [
  PaymentChannelMeta(
    channel: PaymentChannel.qris,
    group: PaymentChannelGroup.qr,
    label: 'QRIS',
    description: 'Scan QR pakai aplikasi bank atau e-wallet',
  ),
  PaymentChannelMeta.va(PaymentChannel.bca, 'BCA'),
  PaymentChannelMeta.va(PaymentChannel.bri, 'BRI'),
  PaymentChannelMeta.va(PaymentChannel.mandiri, 'Mandiri'),
  PaymentChannelMeta.va(PaymentChannel.bni, 'BNI'),
  PaymentChannelMeta.va(PaymentChannel.permata, 'Permata'),
  PaymentChannelMeta.va(PaymentChannel.danamon, 'Danamon'),
  PaymentChannelMeta.va(PaymentChannel.cimb, 'CIMB', 'CIMB Niaga'),
  PaymentChannelMeta.va(PaymentChannel.btn, 'BTN'),
  PaymentChannelMeta.va(PaymentChannel.doku, 'DOKU'),
  PaymentChannelMeta.va(PaymentChannel.maybank, 'Maybank'),
  PaymentChannelMeta.va(PaymentChannel.bnc, 'BNC', 'Bank Neo Commerce'),
  PaymentChannelMeta.va(PaymentChannel.bss, 'BSS', 'Bank Sahabat Sampoerna'),
  PaymentChannelMeta.va(PaymentChannel.bjb, 'BJB'),
  PaymentChannelMeta.va(PaymentChannel.sinarmas, 'Sinarmas', 'Bank Sinarmas'),
];

/// Where a channel may be used: totals from [minIdr] to [maxIdr] (null: no
/// cap). `PaymentChannelRule` on the server.
class PaymentChannelRule {
  const PaymentChannelRule({
    required this.channel,
    required this.minIdr,
    this.maxIdr,
  });

  final PaymentChannel channel;
  final int minIdr;
  final int? maxIdr;

  bool allows(int totalIdr) =>
      totalIdr >= minIdr && (maxIdr == null || totalIdr <= maxIdr!);
}

/// The gateway checkout goes through and the channels it offers, from
/// `GET /api/cart/checkout/payment-options`.
class PaymentOptions {
  const PaymentOptions({
    required this.gateway,
    required this.rules,
    this.fromServer = true,
  });

  /// What the server gives an app that doesn't say it can open DOKU's page:
  /// Xendit, QRIS below Rp1.450.000 and its five VA banks from it. Used
  /// until the server has answered, and if it can't.
  static const xenditDefault = PaymentOptions(
    gateway: 'xendit',
    fromServer: false,
    rules: [
      PaymentChannelRule(
        channel: PaymentChannel.qris,
        minIdr: 0,
        maxIdr: 1449999,
      ),
      PaymentChannelRule(channel: PaymentChannel.bni, minIdr: 1450000),
      PaymentChannelRule(channel: PaymentChannel.bri, minIdr: 1450000),
      PaymentChannelRule(channel: PaymentChannel.mandiri, minIdr: 1450000),
      PaymentChannelRule(channel: PaymentChannel.permata, minIdr: 1450000),
      PaymentChannelRule(channel: PaymentChannel.cimb, minIdr: 1450000),
    ],
  );

  /// `xendit` or `doku`.
  final String gateway;
  final List<PaymentChannelRule> rules;

  /// Whether the server said so. Only then does checkout tell it which
  /// gateways the app can open: without these rules, the app has to be
  /// routed the way the [xenditDefault] it shows assumes.
  final bool fromServer;

  /// Reads the route's body. A channel this version doesn't know is left
  /// out: the server may offer banks added after this build.
  static PaymentOptions fromJson(Map<String, dynamic> json) {
    final rows = json['channels'];
    return PaymentOptions(
      gateway: json['gateway'] as String? ?? 'xendit',
      rules: [
        if (rows is List)
          for (final row in rows.whereType<Map>())
            if (PaymentChannelX.fromCode(row['channel'] as String?)
                case final channel?)
              PaymentChannelRule(
                channel: channel,
                minIdr: (row['minIdr'] as num?)?.toInt() ?? 0,
                maxIdr: (row['maxIdr'] as num?)?.toInt(),
              ),
      ],
    );
  }

  /// The channels offered at [totalIdr], in the server's order.
  List<PaymentChannel> channelsFor(int totalIdr) => [
    for (final rule in rules)
      if (rule.allows(totalIdr)) rule.channel,
  ];

  /// Every channel offered at some total.
  Set<PaymentChannel> get offered => {for (final rule in rules) rule.channel};

  /// The smallest total [group]'s channels are offered from; null if none are.
  int? minIdrFor(PaymentChannelGroup group) {
    int? min;
    for (final rule in rules) {
      if (_groupOf(rule.channel) != group) continue;
      if (min == null || rule.minIdr < min) min = rule.minIdr;
    }
    return min;
  }

  /// The largest total [group]'s channels are offered to; null if uncapped
  /// or none are.
  int? maxIdrFor(PaymentChannelGroup group) {
    int? max;
    for (final rule in rules) {
      if (_groupOf(rule.channel) != group) continue;
      if (rule.maxIdr == null) return null;
      if (max == null || rule.maxIdr! > max) max = rule.maxIdr;
    }
    return max;
  }
}

PaymentChannelGroup _groupOf(PaymentChannel channel) =>
    channel == PaymentChannel.qris
    ? PaymentChannelGroup.qr
    : PaymentChannelGroup.va;

/// "xendit" pays via a [PaymentChannel]; "wallet" pays from saldo balance.
enum PaymentMethod { xendit, wallet }

/// `CouponType` in `lib/schemas/coupons.ts`. Card-discount coupons were
/// removed on web; these two are the whole vocabulary.
enum CouponType {
  freeShipping('free_shipping'),
  waiveGatewayFee('waive_gateway_fee');

  const CouponType(this.wire);

  final String wire;

  static CouponType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// `CouponSlot` in `lib/schemas/coupons.ts`: a checkout holds at most one
/// coupon per slot. [values] is `COUPON_SLOT_ORDER`, so the picker lists and
/// the request sends them in the same order web does.
enum CouponSlot {
  shipping,
  fee;

  static CouponSlot? fromWire(Object? value) {
    for (final slot in values) {
      if (slot.name == value) return slot;
    }
    return null;
  }
}

/// `CouponIneligibleReason` in `lib/schemas/coupons.ts`.
enum CouponIneligibleReason {
  usageLimit('usage_limit'),
  perUserLimit('per_user_limit'),
  minPurchase('min_purchase'),
  notApplicable('not_applicable');

  const CouponIneligibleReason(this.wire);

  final String wire;

  static CouponIneligibleReason? fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// One row of `list_available_coupons`, as `POST /api/coupons/available`
/// returns it. Ports `AvailableCouponSchema`; ineligible coupons are listed
/// too, with the [reason] the buyer can't use them yet.
class AvailableCoupon {
  const AvailableCoupon({
    required this.couponId,
    required this.code,
    required this.type,
    required this.slot,
    required this.value,
    required this.minPurchase,
    required this.validUntil,
    required this.discountAmount,
    required this.eligible,
    required this.reason,
    required this.remainingUses,
  });

  final int couponId;
  final String code;
  final CouponType type;
  final CouponSlot slot;

  /// The free-shipping cap; null for the fee waiver, which has no amount.
  final int? value;
  final int minPurchase;
  final DateTime? validUntil;
  final int discountAmount;
  final bool eligible;
  final CouponIneligibleReason? reason;
  final int remainingUses;

  /// Null for a row this client can't read — a type added server-side after
  /// this build. Dropped rather than guessed at, as web's `safeParse` does.
  static AvailableCoupon? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['coupon_id'] as num?)?.toInt();
    final type = CouponType.fromWire(raw['type']);
    final slot = CouponSlot.fromWire(raw['slot']);
    if (id == null || type == null || slot == null) return null;
    return AvailableCoupon(
      couponId: id,
      code: raw['code'] as String? ?? '',
      type: type,
      slot: slot,
      value: (raw['value'] as num?)?.toInt(),
      minPurchase: (raw['min_purchase'] as num?)?.toInt() ?? 0,
      validUntil: DateTime.tryParse(raw['valid_until'] as String? ?? ''),
      discountAmount: (raw['discount_amount'] as num?)?.toInt() ?? 0,
      eligible: raw['eligible'] == true,
      reason: CouponIneligibleReason.fromWire(raw['reason']),
      remainingUses: (raw['remaining_uses'] as num?)?.toInt() ?? 0,
    );
  }

  AppliedCoupon toApplied() => AppliedCoupon(
    couponId: couponId,
    type: type,
    slot: slot,
    value: value,
    minPurchase: minPurchase,
  );
}

/// Ports `AppliedCoupon` from `features/checkout/types`. Carries the coupon's
/// own [value] rather than a quoted amount, so the discount is re-derived
/// from the live shipping total the way the lock RPCs derive it.
class AppliedCoupon {
  const AppliedCoupon({
    required this.couponId,
    required this.type,
    required this.slot,
    required this.value,
    required this.minPurchase,
  });

  final int couponId;
  final CouponType type;
  final CouponSlot slot;
  final int? value;
  final int minPurchase;

  bool get waivesGatewayFee => type == CouponType.waiveGatewayFee;
}

/// Ports `CouponSelection`: what each slot holds right now.
class CouponSelection {
  const CouponSelection({this.shipping, this.fee});

  static const empty = CouponSelection();

  final AppliedCoupon? shipping;
  final AppliedCoupon? fee;

  AppliedCoupon? operator [](CouponSlot slot) => switch (slot) {
    CouponSlot.shipping => shipping,
    CouponSlot.fee => fee,
  };

  /// The `couponIds` `/api/cart/checkout` takes, in slot order.
  List<int> get ids => [
    for (final slot in CouponSlot.values)
      if (this[slot] case final coupon?) coupon.couponId,
  ];

  int get count => ids.length;
}
