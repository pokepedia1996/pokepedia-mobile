import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/store_profile.dart';

Map<String, dynamic> _row({
  String? storeName = 'Toko Ash',
  String? contactName = 'Ash',
  String? contactPhone = '08123456789',
  String? districtId = '3273010',
  String? fullAddress = 'Jl. Pallet No. 1',
  String? vacationMode,
  String? vacationUntil,
  List<String>? services,
}) {
  return {
    'user_id': 'seller-1',
    'store_name': storeName,
    'store_slug': 'toko-ash',
    'store_tagline': 'Kartu langka sejak 2019',
    'about_md': '## Tentang kami',
    'contact_name': contactName,
    'contact_phone': contactPhone,
    'province_id': '32',
    'province_name': 'Jawa Barat',
    'city_id': '3273',
    'city_name': 'Kota Bandung',
    'district_id': districtId,
    'district': 'Sukajadi',
    'postal_code': '40161',
    'full_address': fullAddress,
    'accepted_courier_services': services,
    'vacation_mode': vacationMode,
    'vacation_until': vacationUntil,
    'vacation_message': null,
    'items_sold_count': 12,
    'followers_count': 4,
    'is_active': true,
    'is_verified': false,
  };
}

void main() {
  group('StoreProfile.fromRow', () {
    test('maps the storefront columns', () {
      final profile = StoreProfile.fromRow(_row());
      expect(profile.storeName, 'Toko Ash');
      expect(profile.storeSlug, 'toko-ash');
      expect(profile.aboutMd, '## Tentang kami');
      expect(profile.itemsSoldCount, 12);
      expect(profile.followersCount, 4);
    });

    test('a null accepted_courier_services reads as empty, not as a crash', () {
      expect(
        StoreProfile.fromRow(_row(services: null)).acceptedCourierServices,
        isEmpty,
      );
    });

    test('summarises the address in the order a label reads', () {
      expect(
        StoreProfile.fromRow(_row()).addressSummary,
        'Sukajadi, Kota Bandung, Jawa Barat, 40161',
      );
    });
  });

  group('hasPickupAddress', () {
    test('true only when a courier could actually collect', () {
      expect(StoreProfile.fromRow(_row()).hasPickupAddress, isTrue);
    });

    test('any missing piece makes it false', () {
      expect(
        StoreProfile.fromRow(_row(contactPhone: null)).hasPickupAddress,
        isFalse,
      );
      expect(
        StoreProfile.fromRow(_row(districtId: null)).hasPickupAddress,
        isFalse,
      );
      expect(
        StoreProfile.fromRow(_row(fullAddress: '')).hasPickupAddress,
        isFalse,
      );
    });
  });

  group('vacation', () {
    test('no mode means the store is open', () {
      final profile = StoreProfile.fromRow(_row());
      expect(profile.onVacation, isFalse);
      expect(profile.vacationDaysLeft, isNull);
    });

    test('days left rounds up, so a part-day still counts', () {
      final until = DateTime.now().add(const Duration(hours: 25));
      final profile = StoreProfile.fromRow(
        _row(vacationMode: 'soft', vacationUntil: until.toIso8601String()),
      );
      expect(profile.onVacation, isTrue);
      expect(profile.vacationDaysLeft, 2);
    });

    test('a vacation already past reports zero, not a negative', () {
      final profile = StoreProfile.fromRow(
        _row(vacationMode: 'hard', vacationUntil: '2020-01-01T00:00:00Z'),
      );
      expect(profile.vacationDaysLeft, 0);
    });

    test('modes carry the caps set_toko_vacation enforces', () {
      expect(VacationMode.soft.maxDays, 15);
      expect(VacationMode.hard.maxDays, 30);
      expect(VacationMode.fromRaw('soft'), VacationMode.soft);
      expect(VacationMode.fromRaw('hard'), VacationMode.hard);
      expect(VacationMode.fromRaw(null), isNull);
      expect(VacationMode.fromRaw('sabbatical'), isNull);
    });
  });
}
