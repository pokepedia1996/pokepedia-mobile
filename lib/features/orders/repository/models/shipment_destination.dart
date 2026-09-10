/// Where the parcel is going. Only populated once a shipment row exists —
/// before that the buyer's address is still theirs alone.
class ShipmentDestination {
  const ShipmentDestination({
    this.contactName,
    this.contactPhone,
    this.fullAddress,
    this.district,
    this.city,
    this.province,
    this.postalCode,
  });

  factory ShipmentDestination.fromRow(Map<String, dynamic> row) {
    return ShipmentDestination(
      contactName: row['destination_contact_name'] as String?,
      contactPhone: row['destination_contact_phone'] as String?,
      fullAddress: row['destination_full_address'] as String?,
      district: row['destination_district'] as String?,
      city: row['destination_city'] as String?,
      province: row['destination_province'] as String?,
      postalCode: row['destination_postal_code'] as String?,
    );
  }

  final String? contactName;
  final String? contactPhone;
  final String? fullAddress;
  final String? district;
  final String? city;
  final String? province;
  final String? postalCode;

  /// District · city · province · postcode, skipping whatever is missing.
  String get areaLine => [
    district,
    city,
    province,
    postalCode,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  bool get isEmpty =>
      (contactName ?? '').isEmpty &&
      (fullAddress ?? '').isEmpty &&
      areaLine.isEmpty;
}
