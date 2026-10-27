import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/repository/address_repository.dart';
import '../../account/repository/models/address_model.dart';
import '../../account/usecase/address_notifier.dart';
import '../../expansions/usecase/trading_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../presentation/seller_couriers_page.dart';
import '../repository/models/store_profile.dart';
import '../repository/store_profile_repository.dart';
import 'seller_notifier.dart';
import 'store_profile_notifier.dart';

/// Buka Toko: what the steps have gathered, and the write that opens the
/// store once they are done.
///
/// Nothing reaches the server until "Buka toko" — except the phone, whose
/// verification is the server's own and holds for the whole account. So a
/// flow left half way leaves no half-made store, and a verified number is
/// never asked for again, here or before a first checkout or bid.
class StoreSetupDraft {
  StoreSetupDraft({required this.username}) : storeName = username;

  /// The account's username: the default store name, and the name the
  /// courier asks for at pickup.
  final String username;

  String storeName;
  Uint8List? logo;
  Uint8List? banner;

  /// Whether step 1 was filled in rather than put off with "Nanti dulu".
  bool profileSet = false;

  /// The verified number, as the server normalised it (`+62…`).
  String? phone;

  double? latitude;
  double? longitude;
  AreaOption? province;
  AreaOption? city;
  AreaOption? district;
  String postalCode = '';

  /// The street line — "Jl. Ijen No. 25" — written to `full_address`.
  String street = '';

  /// A landmark for the courier — "Rumah pagar hitam".
  String landmark = '';

  /// Also save the pickup point as a delivery address for buying.
  bool alsoShipping = true;

  /// "Atur manual" rather than the recommended couriers.
  bool manualCouriers = false;
  final Set<String> manualServiceIds = {};

  /// Takes a pickup point saved before the store was opened — from Alamat,
  /// which lets anyone set one — so the pickup step starts on it. A pin the
  /// seller has already placed here wins.
  void prefillPickup(StoreProfile profile, AreaCatalog catalog) {
    final lat = profile.pickupLat;
    final lng = profile.pickupLng;
    if (latitude != null || lat == null || lng == null) return;
    latitude = lat;
    longitude = lng;
    province = profile.provinceId == null
        ? null
        : catalog.findProvince(profile.provinceId!);
    city = profile.cityId == null ? null : catalog.findRegency(profile.cityId!);
    district = profile.districtId == null
        ? null
        : catalog.findDistrict(profile.districtId!);
    postalCode = profile.postalCode ?? '';
    street = profile.fullAddress ?? '';
    landmark = profile.notes ?? '';
  }

  bool get pickupReady =>
      latitude != null &&
      longitude != null &&
      province != null &&
      city != null &&
      district != null &&
      street.trim().isNotEmpty;

  /// The address line under the street: "Klojen, Kota Malang, Jawa Timur
  /// 65112".
  String get areaLine {
    final region = [
      province?.name,
      postalCode.trim(),
    ].whereType<String>().where((p) => p.isNotEmpty).join(' ');
    return [
      district?.name,
      city?.name,
      region,
    ].whereType<String>().where((p) => p.isNotEmpty).join(', ');
  }
}

/// The six couriers "Rekomendasi" turns on, in the design's order: the
/// big parcel networks for anywhere, and the two ride-hailing apps for
/// same-day in town.
const recommendedCouriers = <(String code, String label)>[
  ('jne', 'JNE'),
  ('lion', 'Lion Express'),
  ('jnt', 'J&T'),
  ('sicepat', 'SiCepat'),
  ('gojek', 'Gojek'),
  ('grab', 'Grab'),
];

/// Every service of the recommended couriers that the catalog offers.
List<CourierService> recommendedServices(
  Map<CourierBucket, List<CourierService>> catalog,
) {
  final codes = {for (final c in recommendedCouriers) c.$1};
  return [
    for (final services in catalog.values)
      for (final service in services)
        if (codes.contains(service.id.split('/').first)) service,
  ];
}

/// The recommended couriers the catalog has any service for — the chips
/// under "Rekomendasi", and the names the finished store lists.
List<String> recommendedCourierLabels(
  Map<CourierBucket, List<CourierService>> catalog,
) {
  final present = {
    for (final s in recommendedServices(catalog)) s.id.split('/').first,
  };
  return [
    for (final c in recommendedCouriers)
      if (present.contains(c.$1)) c.$2,
  ];
}

/// The store URL from [name], or from [username] when the name makes no
/// usable one — "★★★" has no letters for a slug.
String storeSlugFor(String name, String username) {
  final fromName = slugify(name);
  if (storeSlugPattern.hasMatch(fromName)) return fromName;
  final fromUsername = slugify(username);
  if (storeSlugPattern.hasMatch(fromUsername)) return fromUsername;
  // A username is at least three characters of letters, digits and
  // underscores, so this is only for a name and username that both fail.
  return 'toko-${fromUsername.isEmpty ? 'baru' : fromUsername}';
}

/// What opening the store came to: [error] if it did not open, and
/// [warnings] for the parts after it that did not take — the store is open
/// either way, and they can be redone from its settings.
typedef StoreOpenResult = ({String? error, List<String> warnings});

class StoreSetupController {
  StoreSetupController(this.ref);

  final Ref ref;

  /// Opens the store from [draft] with [serviceIds] as its couriers.
  Future<StoreOpenResult> open(
    StoreSetupDraft draft,
    List<String> serviceIds,
  ) async {
    final phone = draft.phone;
    final province = draft.province;
    final city = draft.city;
    final district = draft.district;
    if (phone == null) {
      return (error: 'Verifikasi nomor HP dulu.', warnings: const <String>[]);
    }
    if (!draft.pickupReady ||
        province == null ||
        city == null ||
        district == null) {
      return (
        error: 'Lengkapi alamat pickup dulu.',
        warnings: const <String>[],
      );
    }

    final repo = ref.read(storeProfileRepositoryProvider);
    final error = await repo.openStore(
      storeName: draft.storeName,
      storeSlug: storeSlugFor(draft.storeName, draft.username),
      pickup: PickupAddress(
        contactName: draft.username,
        contactPhone: phone,
        provinceId: province.code,
        provinceName: province.name,
        cityId: city.code,
        cityName: city.name,
        districtId: district.code,
        districtName: district.name,
        postalCode: draft.postalCode,
        fullAddress: draft.street,
        notes: draft.landmark,
        latitude: draft.latitude!,
        longitude: draft.longitude!,
      ),
      courierServiceIds: serviceIds,
    );
    if (error != null) return (error: error, warnings: const <String>[]);

    final warnings = <String>[];
    for (final (kind, bytes) in [
      (StorefrontImageKind.logo, draft.logo),
      (StorefrontImageKind.banner, draft.banner),
    ]) {
      if (bytes == null) continue;
      final failed = await repo.uploadStorefrontImage(kind: kind, bytes: bytes);
      if (failed != null) {
        warnings.add(
          kind == StorefrontImageKind.logo
              ? 'Foto toko belum tersimpan.'
              : 'Banner belum tersimpan.',
        );
      }
    }

    if (draft.alsoShipping) {
      final failed = await ref
          .read(addressRepositoryProvider)
          .createAddress(
            label: 'Rumah',
            contactName: draft.username,
            contactPhone: phone,
            province: province,
            city: city,
            district: district,
            fullAddress: draft.street,
            postalCode: draft.postalCode,
            notes: draft.landmark,
          );
      if (failed != null) {
        warnings.add('Alamat pengiriman belum tersimpan.');
      } else {
        ref.invalidate(addressesProvider);
      }
    }

    // Everything that asked "has this user got a store?" asks again.
    ref
      ..invalidate(hasStoreProvider)
      ..invalidate(storeProfileProvider)
      ..invalidate(sellerIdentityProvider)
      ..invalidate(tradeEligibilityProvider)
      ..invalidate(privateProfileProvider);
    return (error: null, warnings: warnings);
  }
}

final storeSetupControllerProvider = Provider(StoreSetupController.new);
