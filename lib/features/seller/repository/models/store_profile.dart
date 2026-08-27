/// The seller's own `seller_profiles` row — web's `SellerProfile`, over the
/// columns its `SAFE_STOREFRONT_SELECT` returns.
class StoreProfile {
  const StoreProfile({
    this.storeName,
    this.storeSlug,
    this.storeTagline,
    this.storeLogoUrl,
    this.storeBannerUrl,
    this.aboutMd,
    this.contactName,
    this.contactPhone,
    this.provinceId,
    this.provinceName,
    this.cityId,
    this.cityName,
    this.districtId,
    this.district,
    this.postalCode,
    this.fullAddress,
    this.notes,
    this.pickupLat,
    this.pickupLng,
    this.acceptedCourierServices = const [],
    this.vacationMode,
    this.vacationUntil,
    this.vacationMessage,
    this.itemsSoldCount = 0,
    this.followersCount = 0,
    this.isActive = false,
    this.isVerified = false,
  });

  factory StoreProfile.fromRow(Map<String, dynamic> row) {
    return StoreProfile(
      storeName: row['store_name'] as String?,
      storeSlug: row['store_slug'] as String?,
      storeTagline: row['store_tagline'] as String?,
      storeLogoUrl: row['store_logo_url'] as String?,
      storeBannerUrl: row['store_banner_url'] as String?,
      aboutMd: row['about_md'] as String?,
      contactName: row['contact_name'] as String?,
      contactPhone: row['contact_phone'] as String?,
      provinceId: row['province_id'] as String?,
      provinceName: row['province_name'] as String?,
      cityId: row['city_id'] as String?,
      cityName: row['city_name'] as String?,
      districtId: row['district_id'] as String?,
      district: row['district'] as String?,
      postalCode: row['postal_code'] as String?,
      fullAddress: row['full_address'] as String?,
      notes: row['notes'] as String?,
      pickupLat: (row['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (row['pickup_lng'] as num?)?.toDouble(),
      acceptedCourierServices:
          ((row['accepted_courier_services'] as List?) ?? const [])
              .whereType<String>()
              .toList(),
      vacationMode: row['vacation_mode'] as String?,
      vacationUntil: DateTime.tryParse(
        row['vacation_until'] as String? ?? '',
      )?.toLocal(),
      vacationMessage: row['vacation_message'] as String?,
      itemsSoldCount: (row['items_sold_count'] as num?)?.toInt() ?? 0,
      followersCount: (row['followers_count'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] as bool? ?? false,
      isVerified: row['is_verified'] as bool? ?? false,
    );
  }

  final String? storeName;
  final String? storeSlug;
  final String? storeTagline;
  final String? storeLogoUrl;
  final String? storeBannerUrl;
  final String? aboutMd;

  /// The pickup address a courier collects from.
  final String? contactName;
  final String? contactPhone;
  final String? provinceId;
  final String? provinceName;
  final String? cityId;
  final String? cityName;
  final String? districtId;
  final String? district;
  final String? postalCode;
  final String? fullAddress;
  final String? notes;

  /// Where the map picker last dropped the pin. Biteship books a pickup
  /// against these when they're set.
  final double? pickupLat;
  final double? pickupLng;

  /// Biteship service ids. Empty means the seller has never chosen, which
  /// web reads as "accept everything".
  final List<String> acceptedCourierServices;

  /// `soft` keeps the store browsable but stops new orders; `hard` hides it.
  /// Null when the store is open.
  final String? vacationMode;
  final DateTime? vacationUntil;
  final String? vacationMessage;

  final int itemsSoldCount;
  final int followersCount;
  final bool isActive;
  final bool isVerified;

  bool get onVacation => vacationMode != null;

  /// The slug, or null when it's unset *or blank* — an empty slug would
  /// build `/market/`, a route with no handle segment for the page to read.
  String? get storeHandle =>
      (storeSlug == null || storeSlug!.trim().isEmpty) ? null : storeSlug;

  /// Everything a courier needs to find the place. Web won't book a pickup
  /// without it, so the profile page flags it as the blocking gap.
  bool get hasPickupAddress =>
      (contactName?.isNotEmpty ?? false) &&
      (contactPhone?.isNotEmpty ?? false) &&
      (districtId?.isNotEmpty ?? false) &&
      (fullAddress?.isNotEmpty ?? false);

  String get addressSummary {
    final parts = [
      district,
      cityName,
      provinceName,
      postalCode,
    ].where((p) => p != null && p.isNotEmpty).cast<String>();
    return parts.join(', ');
  }

  /// How many days of vacation are left, rounded up — what web prints on the
  /// "sedang libur" banner.
  int? get vacationDaysLeft {
    final until = vacationUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    if (left.isNegative) return 0;
    // Rounded up from minutes, not hours: `inHours` truncates first, so a
    // day and one hour left would otherwise read as a single day.
    return (left.inMinutes / Duration.minutesPerDay).ceil();
  }
}

/// Web's two vacation modes and the caps `set_toko_vacation` enforces.
enum VacationMode {
  soft(
    'soft',
    'Buka',
    'Listing tetap tampil. Pembeli bisa checkout, pengiriman tertunda hingga '
        'toko aktif kembali.',
    15,
  ),
  hard(
    'hard',
    'Pause penjualan',
    'Listing disembunyikan. Pembeli tidak bisa checkout dari toko kamu.',
    30,
  );

  const VacationMode(this.raw, this.label, this.description, this.maxDays);

  final String raw;
  final String label;
  final String description;

  /// What the radio prints — web appends the cap to the label.
  String get title => '$label (maks. $maxDays hari)';

  /// The server caps this too — 15 days for soft, 30 for hard — so the form
  /// refuses past it rather than posting a request that will be rejected.
  final int maxDays;

  static VacationMode? fromRaw(String? raw) => switch (raw) {
    'soft' => VacationMode.soft,
    'hard' => VacationMode.hard,
    _ => null,
  };
}

/// Ports `StorefrontImageKind` and `STOREFRONT_KIND_PRESETS`.
enum StorefrontImageKind {
  logo('store_logo_url', 512, 512, 'Logo'),
  banner('store_banner_url', 1500, 500, 'Banner');

  const StorefrontImageKind(this.column, this.width, this.height, this.label);

  final String column;

  /// What the image is cropped and scaled to before upload, matching web's
  /// presets so a store looks the same whichever client set it.
  final int width;
  final int height;
  final String label;

  double get aspect => width / height;
}
