import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import 'models/store_profile.dart';

/// The seller's store settings — web's `/seller/settings` and
/// `/seller/couriers`.
///
/// Web routes these through `PUT /api/seller/profile`, but every section of
/// that handler either upserts `seller_profiles` or calls an RPC granted to
/// `authenticated`:
///
/// * `seller_profiles_self_update` / `_self_insert` cover the owner's own row,
///   and `protect_admin_columns` only guards the counters (`items_sold_count`,
///   `followers_count`), none of which this writes.
/// * `resolve_unique_store_slug` and `set_toko_vacation` are both granted to
///   `authenticated` and read `auth.uid()` themselves.
///
/// So this talks to Postgres directly and stays off pokepedia.id, which sits
/// behind a firewall the app can't reliably clear.
class StoreProfileRepository {
  StoreProfileRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Ports `SAFE_STOREFRONT_SELECT`.
  static const _columns =
      'user_id, accepted_couriers, accepted_courier_services, is_active,'
      'contact_name, contact_phone, province_id, province_name, city_id,'
      'city_name, district_id, district, postal_code, full_address,'
      'pickup_lat, pickup_lng, notes, store_name, store_slug, store_logo_url,'
      'store_banner_url, store_tagline, featured_listing_ids,'
      'featured_expansion_codes, marketing_banner_text, store_display_mode,'
      'about_md, items_sold_count, followers_count, top_rated, is_verified,'
      'default_auto_relist, default_accepts_offers, vacation_mode,'
      'vacation_until, vacation_started_at, vacation_message';

  Future<StoreProfile?> fetch() async {
    final userId = _uid;
    if (userId == null) return null;

    final row = await _client
        .from('seller_profiles')
        .select(_columns)
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : StoreProfile.fromRow(row);
  }

  /// Web's `storefront` section: name, URL and tagline.
  ///
  /// The slug goes through `resolve_unique_store_slug` first, exactly as the
  /// route does — two sellers can ask for "toko-ash", and the RPC is what
  /// decides who gets it and what the other one becomes.
  Future<String?> saveStorefront({
    required String storeName,
    required String storeSlug,
    String? tagline,
  }) async {
    final userId = _uid;
    if (userId == null) return 'Sesi berakhir.';
    if (storeName.trim().isEmpty) return 'Nama toko tidak boleh kosong.';

    try {
      final resolved = await _client.rpc(
        'resolve_unique_store_slug',
        params: {'p_base': storeSlug, 'p_exclude_id': userId},
      );
      final finalSlug = resolved as String?;
      if (finalSlug == null || finalSlug.isEmpty) {
        return 'Nama toko tidak valid.';
      }

      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        'store_name': storeName.trim(),
        'store_slug': finalSlug,
        'store_tagline': _nullIfBlank(tagline),
      }, onConflict: 'user_id');
      return null;
    } on PostgrestException catch (e) {
      // The slug is unique-constrained: another seller can take it between
      // the resolve and the write.
      if (e.code == '23505') {
        return 'URL toko itu baru saja dipakai orang lain. Coba lagi.';
      }
      return e.message;
    }
  }

  /// Web's `about` section.
  Future<String?> saveAbout(String? aboutMd) async {
    final userId = _uid;
    if (userId == null) return 'Sesi berakhir.';
    try {
      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        'about_md': _nullIfBlank(aboutMd),
      }, onConflict: 'user_id');
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Web's default (address) section — the pickup point a courier collects
  /// from. The area names are resolved from the app's bundled catalog rather
  /// than Biteship, so this works offline and without the API key.
  Future<String?> savePickupAddress({
    required String contactName,
    required String contactPhone,
    required String provinceId,
    required String provinceName,
    required String cityId,
    required String cityName,
    required String districtId,
    required String districtName,
    required String postalCode,
    required String fullAddress,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _uid;
    if (userId == null) return 'Sesi berakhir.';
    try {
      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        'contact_name': contactName.trim(),
        'contact_phone': contactPhone.trim(),
        'province_id': provinceId,
        'province_name': provinceName,
        'city_id': cityId,
        'city_name': cityName,
        'district_id': districtId,
        'district': districtName,
        'postal_code': postalCode.trim(),
        'full_address': fullAddress.trim(),
        'notes': _nullIfBlank(notes),
        'pickup_lat': latitude,
        'pickup_lng': longitude,
      }, onConflict: 'user_id');
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Web's `vacation` section. The RPC owns the rules — mode, the day cap per
  /// mode, and the `vacation_until` it derives — so this passes the request
  /// through rather than computing a date the server would recompute anyway.
  ///
  /// [mode] null ends the vacation early.
  Future<String?> saveVacation({
    VacationMode? mode,
    int? days,
    String? message,
  }) async {
    if (_uid == null) return 'Sesi berakhir.';
    try {
      final result = await _client.rpc(
        'set_toko_vacation',
        params: {
          'p_mode': mode?.raw,
          'p_days': days,
          'p_message': _nullIfBlank(message),
        },
      );
      if (result is! Map) return 'Gagal menyimpan pengaturan libur.';
      if (result['ok'] == true) return null;

      return switch (result['error']) {
        'vacation_days_exceed_cap' =>
          'Durasi libur melebihi batas maksimal '
              '${result['max_days'] ?? mode?.maxDays} hari.',
        'invalid_vacation_days' => 'Durasi libur tidak valid.',
        'invalid_vacation_mode' => 'Mode libur tidak valid.',
        'unauthorized' => 'Sesi berakhir.',
        _ => 'Gagal menyimpan pengaturan libur.',
      };
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Web's `storefront_image` section, plus the upload that precedes it.
  ///
  /// `uploadStorefrontImage` in web writes straight to Storage from the
  /// browser and only posts the resulting URL to the API; the app does the
  /// same. The `storefronts` bucket is public to read and its insert policy
  /// is `(storage.foldername(name))[1] = auth.uid()::text`, which is exactly
  /// the path built here — so no server round trip is involved at all.
  ///
  /// Returns an error message, or null on success.
  Future<String?> uploadStorefrontImage({
    required StorefrontImageKind kind,
    required Uint8List bytes,
    String? previousUrl,
  }) async {
    final userId = _uid;
    if (userId == null) return 'Sesi berakhir.';
    if (bytes.lengthInBytes > _maxUploadBytes) {
      return 'File terlalu besar (maks 4.5MB)';
    }

    final bucket = _client.storage.from(_storefrontBucket);
    final path =
        '$userId/${kind.name}-'
        '${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
      final url = bucket.getPublicUrl(path);

      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        kind.column: url,
      }, onConflict: 'user_id');

      // Only after the row points at the new file: deleting first would
      // leave the store with a broken image if the upsert failed.
      if (previousUrl != null) {
        final previousPath = storefrontPathOf(previousUrl);
        if (previousPath != null && previousPath != path) {
          try {
            await bucket.remove([previousPath]);
          } on StorageException {
            // An orphaned file costs a few KB; failing the save over it
            // would cost the seller their new logo.
          }
        }
      }
      return null;
    } on StorageException catch (e) {
      return e.message;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Web's `couriers` section — the Biteship service ids this seller ships
  /// with.
  ///
  /// A service id is `courier/service`, and `accepted_couriers` is the set of
  /// courier halves. Derived here rather than asked of the caller so the two
  /// columns can't drift apart, which is what the route does too.
  Future<String?> saveCouriers(List<String> serviceIds) async {
    final userId = _uid;
    if (userId == null) return 'Sesi berakhir.';
    if (serviceIds.isEmpty) return 'Pilih minimal 1 layanan kurir.';
    try {
      final courierCodes = {
        for (final id in serviceIds) id.split('/').first,
      }.toList();
      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        'accepted_courier_services': serviceIds,
        'accepted_couriers': courierCodes,
      }, onConflict: 'user_id');
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }
}

/// Ports `extractStorefrontPath` — the object path inside the bucket, which
/// is what Storage's `remove` takes.
String? storefrontPathOf(String publicUrl) {
  final match = RegExp(r'storefronts/(.+)$').firstMatch(publicUrl);
  return match?.group(1);
}

const _storefrontBucket = 'storefronts';

/// Web caps the source file at 4.5MB before compressing.
const _maxUploadBytes = 4.5 * 1024 * 1024;

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

final storeProfileRepositoryProvider = Provider(
  (ref) => StoreProfileRepository(ref.read(supabaseClientProvider)),
);
