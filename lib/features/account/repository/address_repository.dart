import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/geocode.dart';
import 'models/address_model.dart';

const _addressColumns =
    'id, slug, label, contact_name, contact_phone, province_id, province_name, '
    'city_id, city_name, district_id, district, postal_code, full_address, '
    'is_primary, notes, latitude, longitude';

/// Data access for the buyer's address book. Ports `/api/addresses*`, which
/// is a thin wrapper over own-row `user_addresses` writes (full RLS) plus
/// the `set_primary_address` and `delete_address` RPCs — both granted to
/// `authenticated`, so the app performs the same operations directly.
///
/// Region names are resolved from the bundled dataset rather than the
/// server's `idn-area-data` lookup, so an address created here stores the
/// same province/city/district strings the web writes.
class AddressRepository {
  AddressRepository(this._client);

  final SupabaseClient _client;

  Future<List<AddressModel>> fetchAddresses() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('user_addresses')
        .select(_addressColumns)
        .eq('user_id', userId)
        .order('is_primary', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(AddressModel.fromRow).toList();
  }

  /// Inserts an address. Returns null on success, else a message.
  /// The first address a user saves becomes their primary, matching the
  /// web form's default.
  Future<String?> createAddress({
    required String label,
    required String contactName,
    required String contactPhone,
    required AreaOption province,
    required AreaOption city,
    required AreaOption district,
    required String fullAddress,
    String? postalCode,
    String? notes,
    bool makePrimary = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Masuk dulu untuk menyimpan alamat.';

    try {
      final existing = await _client
          .from('user_addresses')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      final isFirst = existing.isEmpty;

      final inserted = await _client
          .from('user_addresses')
          .insert({
            'user_id': userId,
            'label': label,
            'contact_name': contactName,
            'contact_phone': contactPhone,
            'province_id': province.code,
            'province_name': province.name,
            'city_id': city.code,
            'city_name': city.name,
            'district_id': district.code,
            'district': district.name,
            'postal_code': postalCode,
            'full_address': fullAddress,
            'notes': notes,
            'is_primary': isFirst,
          })
          .select('id')
          .single();

      if (makePrimary && !isFirst) {
        await setPrimary((inserted['id'] as num).toInt());
      }
      return null;
    } on PostgrestException catch (e) {
      return _messageFor(e);
    }
  }

  Future<String?> updateAddress({
    required int id,
    required String label,
    required String contactName,
    required String contactPhone,
    required AreaOption province,
    required AreaOption city,
    required AreaOption district,
    required String fullAddress,
    String? postalCode,
    String? notes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Masuk dulu untuk mengubah alamat.';
    try {
      await _client
          .from('user_addresses')
          .update({
            'label': label,
            'contact_name': contactName,
            'contact_phone': contactPhone,
            'province_id': province.code,
            'province_name': province.name,
            'city_id': city.code,
            'city_name': city.name,
            'district_id': district.code,
            'district': district.name,
            'postal_code': postalCode,
            'full_address': fullAddress,
            'notes': notes,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return _messageFor(e);
    }
  }

  Future<String?> setPrimary(int addressId) async {
    try {
      final result = await _client.rpc(
        'set_primary_address',
        params: {'p_address_id': addressId},
      );
      if (result is Map<String, dynamic> && result['error'] != null) {
        return 'Gagal mengatur alamat utama.';
      }
      return null;
    } on PostgrestException catch (e) {
      return _messageFor(e);
    }
  }

  /// Deletes through the RPC rather than the table so the server's own
  /// guard (an address referenced by a live order can't be removed) applies.
  Future<String?> deleteAddress(String slug) async {
    try {
      final result = await _client.rpc(
        'delete_address',
        params: {'p_slug': slug},
      );
      if (result is Map<String, dynamic>) {
        final error = result['error'] as String?;
        if (error != null) {
          return error == 'in_use'
              ? 'Alamat ini sedang dipakai pesanan aktif.'
              : 'Gagal menghapus alamat.';
        }
      }
      return null;
    } on PostgrestException catch (e) {
      return _messageFor(e);
    }
  }

  String _messageFor(PostgrestException e) {
    final message = e.message;
    if (message.contains('user_addresses_postal_code_check')) {
      return 'Kode pos harus 5 angka.';
    }
    if (message.contains('user_addresses_contact_phone_check')) {
      return 'Nomor HP tidak valid.';
    }
    if (message.contains('_check')) return 'Ada isian yang belum valid.';
    return 'Gagal menyimpan alamat. Coba lagi.';
  }
}

/// The bundled province/regency/district dataset, parsed once per app run.
/// Kept out of [AddressRepository] because it's a pure asset lookup with no
/// Supabase involvement.
class AreaCatalog {
  AreaCatalog._(this._provinces, this._regencies, this._districts);

  final List<AreaOption> _provinces;
  final List<AreaOption> _regencies;
  final List<AreaOption> _districts;

  static AreaCatalog? _cached;

  static Future<AreaCatalog> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/data/idn_areas.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    List<AreaOption> parse(String key, String? parentKey) {
      return (json[key] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (e) => AreaOption(
              code: e['c'] as String,
              name: e['n'] as String,
              parentCode: parentKey == null ? null : e[parentKey] as String?,
            ),
          )
          .toList();
    }

    final catalog = AreaCatalog._(
      parse('provinces', null),
      parse('regencies', 'p'),
      parse('districts', 'r'),
    );
    _cached = catalog;
    return catalog;
  }

  List<AreaOption> get provinces => _provinces;

  List<AreaOption> regenciesOf(String provinceCode) =>
      _regencies.where((r) => r.parentCode == provinceCode).toList();

  List<AreaOption> districtsOf(String regencyCode) =>
      _districts.where((d) => d.parentCode == regencyCode).toList();

  AreaOption? findProvince(String code) => _find(_provinces, code);
  AreaOption? findRegency(String code) => _find(_regencies, code);
  AreaOption? findDistrict(String code) => _find(_districts, code);

  static AreaOption? _find(List<AreaOption> list, String code) {
    for (final option in list) {
      if (option.code == code) return option;
    }
    return null;
  }
}

String _normaliseArea(String value) => value
    .toLowerCase()
    .replaceAll(
      RegExp(
        r'\b(kota|kabupaten|kab\.?|provinsi|prov\.?|daerah|khusus|'
        r'ibukota|istimewa|administrasi|adm\.?|kecamatan|kec\.?)\b',
      ),
      '',
    )
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The catalog entry Nominatim's [name] for an area means, or null.
///
/// Compares on the significant part of the name: OSM says "Kota Bandung"
/// where the catalog says "Bandung", and "Daerah Khusus Ibukota Jakarta"
/// where it says "DKI Jakarta", so the administrative words are dropped
/// before comparing — after an exact match has had its chance, since
/// "Kota Malang" and "Kabupaten Malang" are both in the catalog and only
/// the full name tells them apart.
AreaOption? matchAreaOption(List<AreaOption> options, String? name) {
  final matches = matchAreaOptions(options, name);
  return matches.isEmpty ? null : matches.first;
}

/// Every catalog entry [name] could mean, best first: an exact name, then
/// the same significant name, then one containing the other.
List<AreaOption> matchAreaOptions(List<AreaOption> options, String? name) {
  if (name == null || name.trim().isEmpty) return const [];

  final exact = name.trim().toLowerCase();
  final needle = _normaliseArea(name);
  if (needle.isEmpty) return const [];

  final result = <AreaOption>[
    for (final option in options)
      if (option.name.toLowerCase() == exact) option,
  ];
  for (final option in options) {
    if (!result.contains(option) && _normaliseArea(option.name) == needle) {
      result.add(option);
    }
  }
  for (final option in options) {
    final candidate = _normaliseArea(option.name);
    if (!result.contains(option) &&
        candidate.isNotEmpty &&
        (candidate.contains(needle) || needle.contains(candidate))) {
      result.add(option);
    }
  }
  return result;
}

/// The city Nominatim means, with the district settling a tie: "Malang" is
/// both Kota and Kabupaten Malang, and only one of them has Klojen.
AreaOption? matchCity(
  AreaCatalog catalog,
  String provinceCode,
  String? city,
  String? district,
) {
  final candidates = matchAreaOptions(catalog.regenciesOf(provinceCode), city);
  if (candidates.length > 1 && district != null) {
    for (final candidate in candidates) {
      if (matchAreaOption(catalog.districtsOf(candidate.code), district) !=
          null) {
        return candidate;
      }
    }
  }
  return candidates.isEmpty ? null : candidates.first;
}

/// ISO 3166-2 province suffixes, by catalog code. OSM leaves the province's
/// name out across Jakarta but always sends this.
const _provinceCodeByIso = {
  'AC': '11',
  'SU': '12',
  'SB': '13',
  'RI': '14',
  'JA': '15',
  'SS': '16',
  'BE': '17',
  'LA': '18',
  'BB': '19',
  'KR': '21',
  'JK': '31',
  'JB': '32',
  'JT': '33',
  'YO': '34',
  'JI': '35',
  'BT': '36',
  'BA': '51',
  'NB': '52',
  'NT': '53',
  'KB': '61',
  'KT': '62',
  'KS': '63',
  'KI': '64',
  'KU': '65',
  'SA': '71',
  'ST': '72',
  'SN': '73',
  'SG': '74',
  'GO': '75',
  'SR': '76',
  'MA': '81',
  'MU': '82',
  'PA': '91',
  'PB': '92',
  'PS': '93',
  'PT': '94',
  'PE': '95',
  'PD': '96',
};

/// The province, kota/kabupaten and kecamatan a geocoder [result] lands
/// in, each null where the catalog can't be sure. A level left null goes to
/// "Ubah" rather than being guessed: a wrong district code sends the courier
/// to the wrong place.
({AreaOption? province, AreaOption? city, AreaOption? district}) resolveArea(
  AreaCatalog catalog,
  GeocodeResult result,
) {
  final iso = _provinceCodeByIso[result.provinceIso];
  final province =
      matchAreaOption(catalog.provinces, result.province) ??
      (iso == null ? null : catalog.findProvince(iso));
  if (province == null) return (province: null, city: null, district: null);

  // The single best guesses lead, for a result built by hand.
  final cityNames = {?result.city, ...result.cityNames};
  final districtNames = {?result.district, ...result.districtNames};

  final provinceName = _normaliseArea(province.name);
  AreaOption? city;
  for (final name in cityNames) {
    // Jakarta's `city` can be the province itself, which would otherwise
    // contain-match every kota in it and pick the first.
    if (_normaliseArea(name) == provinceName) continue;
    final candidates = matchAreaOptions(
      catalog.regenciesOf(province.code),
      name,
    );
    if (candidates.isEmpty) continue;
    // "Malang" is both Kota and Kabupaten Malang; the kecamatan settles it.
    city = candidates.firstWhere(
      (c) => districtNames.any(
        (d) => matchAreaOption(catalog.districtsOf(c.code), d) != null,
      ),
      orElse: () => candidates.first,
    );
    break;
  }
  if (city == null) return (province: province, city: null, district: null);

  final districts = catalog.districtsOf(city.code);
  AreaOption? district;
  for (final name in districtNames) {
    district = matchAreaOption(districts, name);
    if (district != null) break;
  }
  final village = result.village;
  if (district == null && village != null) {
    // A kelurahan often shares its kecamatan's name ("Gambir" in Gambir),
    // but only an exact match is safe: "Menteng Atas" is not in Menteng.
    final needle = _normaliseArea(village);
    for (final option in districts) {
      if (_normaliseArea(option.name) == needle) district = option;
    }
  }
  return (province: province, city: city, district: district);
}
