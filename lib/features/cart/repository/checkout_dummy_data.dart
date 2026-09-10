import 'models/checkout_models.dart';

/// Dummy data standing in for the web's address book, Biteship shipping
/// rate lookups, and wallet/coupon APIs while this pass only ports the
/// checkout UI.
class CheckoutDummyData {
  CheckoutDummyData._();

  static const walletBalance = 350000;

  static const addresses = [
    CheckoutAddress(
      id: 1,
      label: 'Rumah',
      contactName: 'Ash Ketchum',
      contactPhone: '0812-3456-7890',
      fullAddress: 'Jl. Pallet Town No. 1',
      district: 'Kecamatan Pallet',
      cityName: 'Jakarta Selatan',
      provinceName: 'DKI Jakarta',
      postalCode: '12345',
      isPrimary: true,
    ),
    CheckoutAddress(
      id: 2,
      label: 'Kantor',
      contactName: 'Ash Ketchum',
      contactPhone: '0812-3456-7890',
      fullAddress: 'Jl. Indigo Plateau No. 8, Lt. 5',
      district: 'Kecamatan Menteng',
      cityName: 'Jakarta Pusat',
      provinceName: 'DKI Jakarta',
      postalCode: '10310',
      isPrimary: false,
    ),
  ];

  /// Deterministic per-seller courier quotes covering all four buckets.
  static List<CourierOption> courierOptionsFor(String sellerId) {
    final variance = (sellerId.hashCode.abs() % 5) * 1000;
    return [
      CourierOption(
        courier: 'gosend',
        courierName: 'GoSend',
        service: 'Instant',
        description: 'Instant',
        cost: 22000 + variance,
        durationRange: '1-3',
        durationUnit: 'hour',
      ),
      CourierOption(
        courier: 'grab',
        courierName: 'GrabExpress',
        service: 'Same Day',
        description: 'Same Day',
        cost: 18000 + variance,
        durationRange: '6-12',
        durationUnit: 'hour',
        insuranceAvailable: true,
        insuranceFee: 3000,
      ),
      CourierOption(
        courier: 'jne',
        courierName: 'JNE',
        service: 'YES',
        description: 'Yakin Esok Sampai',
        cost: 20000 + variance,
        durationRange: '1',
        durationUnit: 'day',
        insuranceAvailable: true,
        insuranceFee: 2500,
      ),
      CourierOption(
        courier: 'jne',
        courierName: 'JNE',
        service: 'REG',
        description: 'Reguler',
        cost: 15000 + variance,
        durationRange: '2-3',
        durationUnit: 'day',
        insuranceAvailable: true,
        insuranceFee: 2000,
      ),
      CourierOption(
        courier: 'sicepat',
        courierName: 'SiCepat',
        service: 'BEST',
        description: 'Best Economy',
        cost: 16000 + variance,
        durationRange: '2-4',
        durationUnit: 'day',
        insuranceAvailable: true,
        insuranceFee: 2200,
      ),
    ];
  }

  /// Dummy stand-in for the coupon redemption API — only "POKEPEDIA" (the
  /// code hinted at in the input's placeholder) succeeds, waiving the
  /// platform gateway fee.
  static ({bool ok, AppliedCoupon? coupon, String? message}) applyCoupon(
    String code,
    int gatewayFee,
  ) {
    if (code == 'POKEPEDIA') {
      return (
        ok: true,
        coupon: AppliedCoupon(
          code: code,
          waivesGatewayFee: true,
          discountAmount: gatewayFee,
        ),
        message: null,
      );
    }
    return (ok: false, coupon: null, message: 'Kode promo tidak valid');
  }
}
