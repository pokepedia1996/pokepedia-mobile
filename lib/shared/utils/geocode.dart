import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    this.postalCode,
    this.displayName,
  });

  final String? province;
  final String? city;
  final String? district;
  final String? postalCode;
  final String? displayName;

  static const empty = GeocodeResult();
}

class PlaceResult extends GeocodeResult {
  const PlaceResult({
    required this.latitude,
    required this.longitude,
    super.province,
    super.city,
    super.district,
    super.postalCode,
    super.displayName,
  });

  final double latitude;
  final double longitude;
}

const _timeout = Duration(seconds: 5);

/// Nominatim's usage policy requires a real identifying User-Agent and will
/// block clients that don't send one.
const _userAgent = 'PokepediaMobile/1.0 (https://pokepedia.id)';

GeocodeResult _parse(Map<String, dynamic>? address, Object? displayName) {
  final a = address ?? const {};
  return GeocodeResult(
    province: a['state'] as String?,
    city: (a['city'] ?? a['county'] ?? a['town']) as String?,
    district: (a['suburb'] ?? a['village'] ?? a['city_district']) as String?,
    postalCode: a['postcode'] as String?,
    displayName: displayName?.toString().substring(
      0,
      displayName.toString().length.clamp(0, 300),
    ),
  );
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
  return _parse(json['address'] as Map<String, dynamic>?, json['display_name']);
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

    final parsed = _parse(
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
        postalCode: parsed.postalCode,
        displayName: parsed.displayName,
      ),
    );
  }
  return results;
}
