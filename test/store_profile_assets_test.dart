import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/features/seller/repository/models/store_profile.dart';
import 'package:pokepedia_mobile/features/seller/repository/store_profile_repository.dart';
import 'package:pokepedia_mobile/shared/utils/image_crop.dart';

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

void main() {
  group('StorefrontImageKind', () {
    test('carries web\'s presets and target columns', () {
      expect(StorefrontImageKind.logo.width, 512);
      expect(StorefrontImageKind.logo.height, 512);
      expect(StorefrontImageKind.logo.column, 'store_logo_url');

      expect(StorefrontImageKind.banner.width, 1500);
      expect(StorefrontImageKind.banner.height, 500);
      expect(StorefrontImageKind.banner.column, 'store_banner_url');
      expect(StorefrontImageKind.banner.aspect, 3);
    });
  });

  group('cropToAspect', () {
    test('a too-wide source is trimmed at the sides, not squashed', () {
      // 1000x200 (5:1) into a 3:1 banner: the height is already right, so
      // the sides come off rather than the image being scaled unevenly.
      final out = cropToAspect(
        _png(1000, 200),
        targetWidth: 1500,
        targetHeight: 500,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 1500);
      expect(decoded.height, 500);
    });

    test('a too-tall source is trimmed top and bottom', () {
      final out = cropToAspect(
        _png(400, 1200),
        targetWidth: 512,
        targetHeight: 512,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('a source already at the target aspect is only scaled', () {
      final out = cropToAspect(
        _png(3000, 1000),
        targetWidth: 1500,
        targetHeight: 500,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 1500);
      expect(decoded.height, 500);
    });

    test('bytes that are not an image return null rather than throwing', () {
      expect(
        cropToAspect(
          Uint8List.fromList([1, 2, 3, 4]),
          targetWidth: 512,
          targetHeight: 512,
        ),
        isNull,
      );
    });
  });

  group('storefrontPathOf', () {
    test('extracts the object path Storage.remove expects', () {
      expect(
        storefrontPathOf(
          'https://abc.supabase.co/storage/v1/object/public/storefronts/'
          'user-1/logo-123.jpg',
        ),
        'user-1/logo-123.jpg',
      );
    });

    test('a URL from another bucket yields nothing to delete', () {
      expect(
        storefrontPathOf(
          'https://abc.supabase.co/storage/v1/object/public/listing-photos/'
          'user-1/a.jpg',
        ),
        isNull,
      );
    });
  });

  group('VacationMode', () {
    test('titles read the way web prints them', () {
      expect(VacationMode.soft.title, 'Buka (maks. 15 hari)');
      expect(VacationMode.hard.title, 'Pause penjualan (maks. 30 hari)');
    });
  });

  group('StoreProfile pickup coordinates', () {
    test('reads the map pin back off the row', () {
      final profile = StoreProfile.fromRow({
        'pickup_lat': -6.9147,
        'pickup_lng': 107.6098,
      });
      expect(profile.pickupLat, closeTo(-6.9147, 0.0001));
      expect(profile.pickupLng, closeTo(107.6098, 0.0001));
    });

    test('a store that never pinned a point reads null', () {
      final profile = StoreProfile.fromRow(const {});
      expect(profile.pickupLat, isNull);
      expect(profile.pickupLng, isNull);
    });
  });
}
