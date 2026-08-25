/// A saved delivery address, mirroring `public.user_addresses` and the
/// `Address` shape `features/address/api/addresses.ts` maps rows into.
class AddressModel {
  const AddressModel({
    required this.id,
    required this.slug,
    required this.label,
    required this.contactName,
    required this.contactPhone,
    required this.provinceId,
    required this.provinceName,
    required this.cityId,
    required this.cityName,
    required this.districtId,
    required this.district,
    required this.fullAddress,
    required this.isPrimary,
    this.postalCode,
    this.notes,
    this.latitude,
    this.longitude,
  });

  final int id;

  /// `user_addresses.slug` — the public handle the delete RPC takes.
  final String slug;
  final String label;
  final String contactName;
  final String contactPhone;
  final String provinceId;
  final String provinceName;
  final String cityId;
  final String cityName;
  final String districtId;
  final String district;
  final String fullAddress;
  final bool isPrimary;
  final String? postalCode;
  final String? notes;

  /// The map pinpoint, when the buyer set one. Checkout passes it to the
  /// courier quote: with coordinates on both ends Biteship skips the postal
  /// lookup, and instant couriers are only offered to an address that has
  /// one.
  final double? latitude;
  final double? longitude;

  bool get hasPinpoint => latitude != null && longitude != null;

  /// "Kecamatan, Kota, Provinsi 12345" — the one-line form used under the
  /// label in the address list and the checkout picker.
  String get areaLine {
    final parts = [district, cityName, provinceName].where((p) => p.isNotEmpty);
    final area = parts.join(', ');
    return postalCode == null ? area : '$area $postalCode';
  }

  factory AddressModel.fromRow(Map<String, dynamic> row) {
    return AddressModel(
      id: (row['id'] as num).toInt(),
      slug: row['slug'] as String? ?? '',
      label: row['label'] as String? ?? '',
      contactName: row['contact_name'] as String? ?? '',
      contactPhone: row['contact_phone'] as String? ?? '',
      provinceId: row['province_id'] as String? ?? '',
      provinceName: row['province_name'] as String? ?? '',
      cityId: row['city_id'] as String? ?? '',
      cityName: row['city_name'] as String? ?? '',
      districtId: row['district_id'] as String? ?? '',
      district: row['district'] as String? ?? '',
      fullAddress: row['full_address'] as String? ?? '',
      isPrimary: row['is_primary'] as bool? ?? false,
      postalCode: row['postal_code'] as String?,
      notes: row['notes'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
    );
  }
}

/// One entry of the bundled Indonesian area dataset
/// (`assets/data/idn_areas.json`, generated from the same `idn-area-data`
/// package the web validates against). [parentCode] is the province for a
/// regency and the regency for a district.
class AreaOption {
  const AreaOption({required this.code, required this.name, this.parentCode});

  final String code;
  final String name;
  final String? parentCode;
}
