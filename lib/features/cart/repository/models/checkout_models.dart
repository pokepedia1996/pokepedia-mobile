import 'package:flutter/material.dart';

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
    icon: Icons.bolt,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.sameDay,
    title: 'Same Day',
    caption: '6-12 jam',
    icon: Icons.bolt,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.overnight,
    title: 'Overnight',
    caption: 'Besok sampai',
    icon: Icons.local_shipping_outlined,
  ),
  CourierBucketMeta(
    bucket: CourierBucket.regular,
    title: 'Reguler',
    caption: '2-5 hari',
    icon: Icons.local_shipping_outlined,
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

/// Ports `PaymentChannel` / `PaymentChannelMeta` from `lib/payments/pricing.ts`.
enum PaymentChannel { qris, bni, bri, mandiri, permata, cimb }

extension PaymentChannelX on PaymentChannel {
  /// The wire value `/api/cart/checkout` expects — the uppercase keys of
  /// `CHANNEL_TO_XENDIT_PAYMENT_METHOD` in `lib/payments/pricing.ts`.
  /// (BCA is defined server-side but commented out of `VA_CHANNELS` pending
  /// Xendit activation, so it is deliberately absent here too.)
  String get code => name.toUpperCase();
}

enum PaymentChannelGroup { qr, va }

class PaymentChannelMeta {
  const PaymentChannelMeta({
    required this.channel,
    required this.group,
    required this.label,
    required this.description,
  });

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
  PaymentChannelMeta(
    channel: PaymentChannel.bni,
    group: PaymentChannelGroup.va,
    label: 'BNI Virtual Account',
    description: 'Transfer ke nomor VA BNI',
  ),
  PaymentChannelMeta(
    channel: PaymentChannel.bri,
    group: PaymentChannelGroup.va,
    label: 'BRI Virtual Account',
    description: 'Transfer ke nomor VA BRI',
  ),
  PaymentChannelMeta(
    channel: PaymentChannel.mandiri,
    group: PaymentChannelGroup.va,
    label: 'Mandiri Virtual Account',
    description: 'Transfer ke nomor VA Mandiri',
  ),
  PaymentChannelMeta(
    channel: PaymentChannel.permata,
    group: PaymentChannelGroup.va,
    label: 'Permata Virtual Account',
    description: 'Transfer ke nomor VA Permata',
  ),
  PaymentChannelMeta(
    channel: PaymentChannel.cimb,
    group: PaymentChannelGroup.va,
    label: 'CIMB Virtual Account',
    description: 'Transfer ke nomor VA CIMB Niaga',
  ),
];

/// "xendit" pays via a [PaymentChannel]; "wallet" pays from saldo balance.
enum PaymentMethod { xendit, wallet }

/// Ports `AppliedCoupon` from `features/checkout/types.ts`.
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.waivesGatewayFee,
    required this.discountAmount,
  });

  final String code;
  final bool waivesGatewayFee;
  final int discountAmount;
}
