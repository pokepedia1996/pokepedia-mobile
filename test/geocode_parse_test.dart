import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/account/repository/address_repository.dart';
import 'package:pokepedia_mobile/shared/utils/geocode.dart';

/// Real `address` objects from Nominatim, and the catalog entries each must
/// land on. The pickup step fills its area from these; a level that misses
/// is left for the seller to pick under "Ubah".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String?>> resolve(Map<String, dynamic> address) async {
    final area = resolveArea(
      await AreaCatalog.load(),
      parseNominatim(address, null),
    );
    return [area.province?.name, area.city?.name, area.district?.name];
  }

  test(
    'most of the country: the kecamatan is `district`, not `suburb`',
    () async {
      expect(
        await resolve({
          'suburb': 'Samaan',
          'city': 'Kota Malang',
          'district': 'Klojen',
          'state': 'Jawa Timur',
          'ISO3166-2-lvl4': 'ID-JI',
        }),
        ['Jawa Timur', 'Kota Malang', 'Klojen'],
      );
      expect(
        await resolve({
          'suburb': 'Kebon Pisang',
          'district': 'Sumur Bandung',
          'city': 'Kota Bandung',
          'state': 'Jawa Barat',
          'ISO3166-2-lvl4': 'ID-JB',
        }),
        ['Jawa Barat', 'Kota Bandung', 'Sumur Bandung'],
      );
    },
  );

  test('Jakarta, reverse: the city is the province', () async {
    expect(
      await resolve({
        'village': 'Pondok Pinang',
        'suburb': 'Kebayoran Lama',
        'city_district': 'Jakarta Selatan',
        'city': 'Daerah Khusus Ibukota Jakarta',
        'ISO3166-2-lvl4': 'ID-JK',
      }),
      [
        'Daerah Khusus Ibukota Jakarta',
        'Kota Administrasi Jakarta Selatan',
        'Kebayoran Lama',
      ],
    );
  });

  test('Jakarta, search: the city is the kota, no province name', () async {
    expect(
      await resolve({
        'road': 'Jalan Gunung Sahari Raya',
        'village': 'Pademangan Barat',
        'suburb': 'Pademangan',
        'city': 'Jakarta Utara',
        'ISO3166-2-lvl4': 'ID-JK',
      }),
      [
        'Daerah Khusus Ibukota Jakarta',
        'Kota Administrasi Jakarta Utara',
        'Pademangan',
      ],
    );
  });

  test('no kecamatan in OSM: province and city still fill', () async {
    // Gunung Sahari Selatan is a kelurahan of Kemayoran; OSM has no
    // Kemayoran boundary there, so the kecamatan is left for "Ubah".
    expect(
      await resolve({
        'road': 'Jalan Bungur Besar Raya',
        'village': 'Gunung Sahari Selatan',
        'city_district': 'Jakarta Pusat',
        'city': 'Daerah Khusus Ibukota Jakarta',
        'ISO3166-2-lvl4': 'ID-JK',
      }),
      [
        'Daerah Khusus Ibukota Jakarta',
        'Kota Administrasi Jakarta Pusat',
        null,
      ],
    );
  });

  test('a kelurahan named like its kecamatan stands in for it', () async {
    expect(
      await resolve({
        'village': 'Gambir',
        'city_district': 'Jakarta Pusat',
        'ISO3166-2-lvl4': 'ID-JK',
      }),
      [
        'Daerah Khusus Ibukota Jakarta',
        'Kota Administrasi Jakarta Pusat',
        'Gambir',
      ],
    );
  });

  test('every ISO province code points at a catalog province', () async {
    final catalog = await AreaCatalog.load();
    for (final iso in [
      'AC', 'SU', 'SB', 'RI', 'JA', 'SS', 'BE', 'LA', 'BB', 'KR', 'JK', 'JB', //
      'JT', 'YO', 'JI', 'BT', 'BA', 'NB', 'NT', 'KB', 'KT', 'KS', 'KI', 'KU',
      'SA', 'ST', 'SN', 'SG', 'GO', 'SR', 'MA', 'MU', 'PA', 'PB', 'PS', 'PT',
      'PE', 'PD',
    ]) {
      final area = resolveArea(catalog, GeocodeResult(provinceIso: iso));
      expect(area.province, isNotNull, reason: iso);
    }
  });
}
