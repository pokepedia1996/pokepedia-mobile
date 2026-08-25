import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

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
