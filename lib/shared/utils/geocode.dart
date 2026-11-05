import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Ports `features/address/location/geocode.ts` — Nominatim lookups for the
/// map picker.
///
/// Same service web uses, same parsing, same Indonesian-only search. Both
/// calls answer with empty rather than throwing: the map still works without
/// a name for the pin, and the seller can always type the address by hand.
class GeocodeResult {
  const GeocodeResult({
    this.province,
    this.city,
    this.district,
    this.provinceIso,
    this.cityNames = const [],
    this.districtNames = const [],
    this.village,
    this.postalCode,
    this.displayName,
    this.street,
  });

  final String? province;
  final String? city;
  final String? district;

  /// The province's ISO 3166-2 suffix, "JK" for `ID-JK`. OSM sends it even
  /// where it leaves out the province's name, as it does across Jakarta.
  final String? provinceIso;

  /// Every name OSM gave that could be the kota/kabupaten, likeliest first.
  /// Which key holds it depends on the region and on search versus reverse,
  /// so the catalog decides rather than a fixed key.
  final List<String> cityNames;

  /// The same for the kecamatan.
  final List<String> districtNames;

  /// The kelurahan/desa. Only a stand-in for the kecamatan where OSM has no
  /// kecamatan and the two share a name, so it is kept apart from
  /// [districtNames] and matched exactly.
  final String? village;

  final String? postalCode;
  final String? displayName;

  /// The road and house number, where OSM knows them — "Jl. Ijen 25".
  final String? street;

  static const empty = GeocodeResult();
}

class PlaceResult extends GeocodeResult {
  const PlaceResult({
    required this.latitude,
    required this.longitude,
    super.province,
    super.city,
    super.district,
    super.provinceIso,
    super.cityNames,
    super.districtNames,
    super.village,
    super.postalCode,
    super.displayName,
    super.street,
  });

  final double latitude;
  final double longitude;
}

const _timeout = Duration(seconds: 5);

/// Nominatim's usage policy requires a real identifying User-Agent and will
/// block clients that don't send one.
const _userAgent = 'PokepediaMobile/1.0 (https://pokepedia.id)';

/// Reads the area levels out of Nominatim's `address`.
///
/// OSM tags Indonesia several ways. Most of the country: `state` is the
/// province, `city` the kota/kabupaten, `district` the kecamatan and
/// `suburb` the kelurahan. Jakarta has no `state` at all, and then either
/// `city` is the province with `city_district` the kota administrasi and
/// `suburb` the kecamatan (reverse), or `city` is "Jakarta Utara" itself
/// (search). Some points have no kecamatan in OSM, only the kelurahan. So each level carries every key that could hold it, and
/// `resolveArea` keeps whichever the catalog recognises.
@visibleForTesting
GeocodeResult parseNominatim(
  Map<String, dynamic>? address,
  Object? displayName,
) {
  final a = address ?? const {};
  List<String> names(List<String> keys) => [
    for (final key in keys)
      if (a[key] case final String value when value.trim().isNotEmpty) value,
  ];

  final iso = a['ISO3166-2-lvl4'] as String?;
  final cityNames = names([
    'city_district',
    'city',
    'county',
    'regency',
    'town',
    'municipality',
  ]);
  final districtNames = names([
    'district',
    'suburb',
    'city_district',
    'municipality',
  ]);
  return GeocodeResult(
    province: a['state'] as String?,
    city: cityNames.firstOrNull,
    district: districtNames.firstOrNull,
    provinceIso: iso != null && iso.startsWith('ID-') ? iso.substring(3) : null,
    cityNames: cityNames,
    districtNames: districtNames,
    village: names(['village']).firstOrNull,
    postalCode: a['postcode'] as String?,
    street: _street(a),
    displayName: displayName?.toString().substring(
      0,
      displayName.toString().length.clamp(0, 300),
    ),
  );
}

String? _street(Map<String, dynamic> a) {
  final road = (a['road'] ?? a['pedestrian'] ?? a['residential']) as String?;
  if (road == null || road.trim().isEmpty) return null;
  final number = a['house_number'] as String?;
  return number == null || number.trim().isEmpty ? road : '$road No. $number';
}

Future<Object?> _get(Uri uri) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final request = await client.getUrl(uri).timeout(_timeout);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != 200) return null;
    return jsonDecode(await response.transform(utf8.decoder).join());
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// What's at this point on the map.
Future<GeocodeResult> reverseGeocode(double lat, double lng) async {
  final json = await _get(
    Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng'
      '&format=json&addressdetails=1&accept-language=id',
    ),
  );
  if (json is! Map<String, dynamic>) return GeocodeResult.empty;
  return parseNominatim(
    json['address'] as Map<String, dynamic>?,
    json['display_name'],
  );
}

/// Places matching a typed query.
///
/// Nominatim forbids per-keystroke autocomplete, so callers must only run
/// this on an explicit submit — the same rule web's copy of this notes.
Future<List<PlaceResult>> searchPlace(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  final json = await _get(
    Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeQueryComponent(trimmed)}&format=json&addressdetails=1'
      '&accept-language=id&countrycodes=id&limit=5',
    ),
  );
  if (json is! List) return const [];

  final results = <PlaceResult>[];
  for (final item in json) {
    if (item is! Map<String, dynamic>) continue;
    final lat = double.tryParse('${item['lat']}');
    final lng = double.tryParse('${item['lon']}');
    if (lat == null || lng == null) continue;

    final parsed = parseNominatim(
      item['address'] as Map<String, dynamic>?,
      item['display_name'],
    );
    results.add(
      PlaceResult(
        latitude: lat,
        longitude: lng,
        province: parsed.province,
        city: parsed.city,
        district: parsed.district,
        provinceIso: parsed.provinceIso,
        cityNames: parsed.cityNames,
        districtNames: parsed.districtNames,
        village: parsed.village,
        postalCode: parsed.postalCode,
        displayName: parsed.displayName,
        street: parsed.street,
      ),
    );
  }
  return results;
}
