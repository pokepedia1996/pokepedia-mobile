import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/account/repository/address_repository.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/account/usecase/address_notifier.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_couriers_page.dart';
import 'package:pokepedia_mobile/features/seller/presentation/store_setup/pickup_step.dart';
import 'package:pokepedia_mobile/features/seller/presentation/store_setup/store_setup_launcher.dart';
import 'package:pokepedia_mobile/features/seller/presentation/store_setup/store_setup_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/store_profile.dart';
import 'package:pokepedia_mobile/features/seller/repository/store_profile_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/store_profile_notifier.dart';
import 'package:pokepedia_mobile/features/seller/usecase/store_setup.dart';
import 'package:pokepedia_mobile/features/user/repository/models/profile_models.dart';
import 'package:pokepedia_mobile/features/user/repository/phone_otp_repository.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/utils/geocode.dart';
import 'package:pokepedia_mobile/shared/utils/id_phone.dart';
import 'package:pokepedia_mobile/shared/widgets/coretan_kit.dart';
import 'package:pokepedia_mobile/shared/widgets/scribble_drawing.dart';

/// Buka Toko: from the Jual tab's launcher, through profile, phone, pickup
/// point and couriers, to an open store — and nothing written until then.
const _me = AppUser(
  id: 'me',
  email: 'me@example.com',
  username: 'mulyana',
  onboarded: true,
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

/// Records the one write that opens a store, and any pictures after it.
class _FakeStoreRepo implements StoreProfileRepository {
  _FakeStoreRepo({this.openError});

  final String? openError;
  final opened = <Map<String, Object?>>[];
  final uploaded = <StorefrontImageKind>[];
  final savedCouriers = <List<String>>[];

  @override
  Future<String?> saveCouriers(List<String> serviceIds) async {
    savedCouriers.add(serviceIds);
    return null;
  }

  @override
  Future<String?> openStore({
    required String storeName,
    required String storeSlug,
    required PickupAddress pickup,
    required List<String> courierServiceIds,
  }) async {
    opened.add({
      'name': storeName,
      'slug': storeSlug,
      'pickup': pickup.toRow(),
      'couriers': courierServiceIds,
    });
    return openError;
  }

  @override
  Future<String?> uploadStorefrontImage({
    required StorefrontImageKind kind,
    required Uint8List bytes,
    String? previousUrl,
  }) async {
    uploaded.add(kind);
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddresses implements AddressRepository {
  final created = <String>[];

  @override
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
    created.add('$fullAddress, ${district.name}, ${city.name}');
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// WhatsApp codes: everything sent is accepted, and 123456 is right.
class _FakeOtp implements PhoneOtpRepository {
  final sent = <String>[];

  @override
  Future<String> send(String phone) async {
    sent.add(phone);
    return phone;
  }

  @override
  Future<void> verify({required String phone, required String code}) async {
    if (code != '123456') {
      throw const ApiException('Kode OTP salah atau sudah kedaluwarsa');
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CourierService _service(String id, String courier) => CourierService(
  id: id,
  courierName: courier,
  serviceName: id.split('/').last.toUpperCase(),
  duration: '1 - 2 days',
);

/// JNE, J&T and Gojek are recommended; AnterAja is not.
final _catalog = <CourierBucket, List<CourierService>>{
  CourierBucket.instant: [_service('gojek/instant', 'Gojek')],
  CourierBucket.reguler: [
    _service('jne/reg', 'JNE'),
    _service('jne/yes', 'JNE'),
    _service('jnt/ez', 'J&T Express'),
    _service('anteraja/reg', 'AnterAja'),
  ],
};

/// Where "Pakai lokasiku" says the phone is, and what Nominatim says is
/// there: a Malang street, with the city only as "Malang".
const _here = LatLng(-7.9727, 112.6250);
const _ijen = GeocodeResult(
  province: 'Jawa Timur',
  city: 'Malang',
  district: 'Klojen',
  postalCode: '65112',
  street: 'Jl. Ijen No. 25',
);

/// Two hits for a typed search, so the list shows rather than one being
/// picked outright.
const _places = [
  PlaceResult(
    latitude: -7.9727,
    longitude: 112.6250,
    displayName: 'Jalan Ijen, Klojen, Kota Malang',
  ),
  PlaceResult(
    latitude: -7.9800,
    longitude: 112.6300,
    displayName: 'Ijen Boulevard, Klojen, Kota Malang',
  ),
];

late AreaCatalog _areas;

/// The drawings keep moving after they draw in, so nothing would ever
/// settle; with "reduce motion" on they are simply there, and the flow can
/// be walked with pumpAndSettle. The motion has its own tests below.
void _stillMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Past the pause before a full code is checked.
Future<void> _settleCode(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

class _Harness {
  _Harness(this.store, this.addresses, this.otp);
  final _FakeStoreRepo store;
  final _FakeAddresses addresses;
  final _FakeOtp otp;
}

Future<_Harness> _openFlow(
  WidgetTester tester, {
  bool phoneVerified = false,
  String? openError,
  List<String>? searched,
}) async {
  tester.view.physicalSize = const Size(430 * 3, 932 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _stillMotion(tester);

  final harness = _Harness(
    _FakeStoreRepo(openError: openError),
    _FakeAddresses(),
    _FakeOtp(),
  );
  final router = GoRouter(
    initialLocation: Routes.openStore,
    routes: [
      GoRoute(
        path: Routes.seller,
        builder: (_, __) => const Scaffold(body: Text('dasbor')),
      ),
      GoRoute(
        path: Routes.openStore,
        builder: (_, __) => const StoreSetupPage(),
      ),
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      privateProfileProvider.overrideWith(
        (ref) async => phoneVerified
            ? const PrivateProfile(phone: '+6281299998888', phoneVerified: true)
            : const PrivateProfile(),
      ),
      storeProfileRepositoryProvider.overrideWithValue(harness.store),
      addressRepositoryProvider.overrideWithValue(harness.addresses),
      addressesProvider.overrideWith((ref) async => const []),
      areaCatalogProvider.overrideWith((ref) async => _areas),
      phoneOtpRepositoryProvider.overrideWithValue(harness.otp),
      courierServicesProvider.overrideWith((ref) async => _catalog),
      currentLocationProvider.overrideWithValue(() async => _here),
      pickupGeocoderProvider.overrideWithValue((
        reverse: (lat, lng) async => _ijen,
        search: (query) async {
          searched?.add(query);
          return _places;
        },
      )),
    ],
  );
  addTearDown(container.dispose);
  // The profile row must have answered before the flow reads it.
  await container.read(authProvider.future);
  await container.read(privateProfileProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) fail('Nothing reads "$text"');
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// Through the pickup step with "Pakai lokasiku", which the fakes answer.
Future<void> _pickupAtIjen(WidgetTester tester) async {
  expect(find.text('Kartu dijemput'), findsOneWidget);
  await _tap(tester, 'Pakai lokasiku');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _areas = await AreaCatalog.load();
  });

  group('the parts', () {
    test('phone numbers, however they are typed', () {
      expect(idPhoneLocalDigits('0812-3456-7890'), '81234567890');
      expect(idPhoneLocalDigits('+62 812 3456 7890'), '81234567890');
      expect(isIdMobileLocal('81234567890'), isTrue);
      expect(isIdMobileLocal('21234567'), isFalse);
      expect(groupIdLocal('81234567890'), '812 3456 7890');
      expect(formatIdPhone('+6281234567890'), '0812 3456 7890');
      expect(maskIdPhone('+6281299994417'), '0812 •••• 4417');
    });

    test('a store URL from its name, else the username', () {
      expect(storeSlugFor('Binder Mulyana', 'mulyana'), 'binder-mulyana');
      // As web's slugify: an underscore is dropped, not hyphenated.
      expect(storeSlugFor('★★★', 'mul_yana'), 'mulyana');
    });

    test('the recommended couriers are the ones the catalog has', () {
      expect(
        recommendedServices(_catalog).map((s) => s.id),
        containsAll(['gojek/instant', 'jne/reg', 'jne/yes', 'jnt/ez']),
      );
      expect(
        recommendedServices(_catalog).map((s) => s.id),
        isNot(contains('anteraja/reg')),
      );
      expect(recommendedCourierLabels(_catalog), ['JNE', 'J&T', 'Gojek']);
    });

    test('courier times, as a seller reads them', () {
      expect(courierDurationLabel('1 - 3', 'hours'), '1–3 jam');
      expect(courierDurationLabel('2 - 3', 'days'), '2–3 hari');
      expect(courierDurationLabel('1', 'days'), 'besok');
      expect(courierDurationLabel('6 - 8', 'hours'), '6–8 jam');
      expect(courierDurationLabel('', 'days'), '');
      expect(
        CourierService.fromJson({
          'id': 'jne/reg',
          'courierName': 'JNE',
          'serviceName': 'REG',
          'durationRange': '2 - 3',
          'durationUnit': 'days',
        }).duration,
        '2–3 hari',
      );
    });

    test('"Malang" is the Malang that has Klojen', () {
      final jatim = matchAreaOption(_areas.provinces, 'Jawa Timur')!;
      final city = matchCity(_areas, jatim.code, 'Malang', 'Klojen');
      expect(city?.name, 'Kota Malang');
      // Without a district to go on, an exact name still decides.
      expect(
        matchCity(_areas, jatim.code, 'Kabupaten Malang', null)?.name,
        'Kabupaten Malang',
      );
    });
  });

  group('the launcher', () {
    Future<void> open(WidgetTester tester, {required bool verified}) async {
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      _stillMotion(tester);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: StoreSetupLauncher()),
          ),
          GoRoute(
            path: Routes.openStore,
            builder: (_, __) => const Text('alur buka toko'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            privateProfileProvider.overrideWith(
              (ref) async => PrivateProfile(phoneVerified: verified),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('what it takes, counted honestly', (tester) async {
      await open(tester, verified: false);
      expect(find.text('100% aman.'), findsOneWidget);
      expect(find.text('0% potongan.'), findsOneWidget);
      expect(find.text('0 dari 3'), findsOneWidget);
      for (final row in [
        'Profil toko',
        'Verifikasi nomor HP',
        'Atur alamat pickup',
        'Pilih kurir',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
    });

    testWidgets('a phone verified elsewhere is already done', (tester) async {
      await open(tester, verified: true);
      expect(find.text('1 dari 3'), findsOneWidget);
      expect(find.text('selesai'), findsOneWidget);
    });

    testWidgets('Mulai buka toko opens the flow', (tester) async {
      await open(tester, verified: false);
      await tester.tap(find.text('Mulai buka toko'));
      await tester.pumpAndSettle();
      expect(find.text('alur buka toko'), findsOneWidget);
    });
  });

  group('the flow', () {
    testWidgets('the profile can wait; the phone is next', (tester) async {
      await _openFlow(tester);
      expect(find.text('Kenalin'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      // The username is the default name.
      expect(find.text('mulyana'), findsWidgets);

      await _tap(tester, 'Nanti dulu');
      expect(find.text('Nomor HP'), findsWidgets);
      expect(find.text('kamu berapa?'), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
    });

    testWidgets('a number, a WhatsApp code, and on to the pickup point', (
      tester,
    ) async {
      final harness = await _openFlow(tester);
      await _tap(tester, 'Nanti dulu');

      await tester.enterText(find.byType(TextField), '0812-3456-7890');
      await tester.pumpAndSettle();
      // Grouped as typed, the 0 dropped: +62 is already in front.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '812 3456 7890',
      );
      expect(find.text('Format nomor sudah benar'), findsOneWidget);

      await _tap(tester, 'Kirim kode via WhatsApp');
      expect(harness.otp.sent, ['+6281234567890']);
      expect(find.text('kode 6 digit.'), findsOneWidget);
      expect(find.text('+62 812 3456 7890'), findsOneWidget);
      expect(find.textContaining('Kirim ulang dalam'), findsOneWidget);

      // Six digits verify on their own, a moment after the last lands.
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(harness.otp.sent, hasLength(1));
      expect(find.text('kode 6 digit.'), findsOneWidget);
      await _settleCode(tester);
      expect(find.text('Nomor HP terverifikasi'), findsOneWidget);
      expect(find.text('Kartu dijemput'), findsOneWidget);
      expect(find.text('3/4'), findsOneWidget);
    });

    testWidgets('a wrong code says so and stays', (tester) async {
      await _openFlow(tester);
      await _tap(tester, 'Nanti dulu');
      await tester.enterText(find.byType(TextField), '81234567890');
      await tester.pumpAndSettle();
      await _tap(tester, 'Kirim kode via WhatsApp');

      await tester.enterText(find.byType(TextField), '000000');
      await _settleCode(tester);
      expect(
        find.text('Kode OTP salah atau sudah kedaluwarsa'),
        findsOneWidget,
      );
      expect(find.text('kode 6 digit.'), findsOneWidget);
      // Emptied for another go.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('a verified phone is not asked for again', (tester) async {
      await _openFlow(tester, phoneVerified: true);
      await _tap(tester, 'Lanjut');
      expect(find.text('Kartu dijemput'), findsOneWidget);

      // And back goes past it too.
      await tester.tap(find.bySemanticsLabel('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('Kenalin'), findsOneWidget);
    });

    testWidgets('the pickup point reads its address from the pin', (
      tester,
    ) async {
      await _openFlow(tester, phoneVerified: true);
      await _tap(tester, 'Lanjut');

      // Nothing to save until there is a place.
      FilledButton save() =>
          tester.widget(find.widgetWithText(FilledButton, 'Simpan alamat'));
      expect(save().onPressed, isNull);

      await _pickupAtIjen(tester);
      expect(find.text('Jl. Ijen No. 25'), findsOneWidget);
      expect(
        find.text('Klojen, Kota Malang, Jawa Timur 65112'),
        findsOneWidget,
      );
      // The courier asks for the account, at its verified number.
      expect(find.text('mulyana · 0812 9999 8888'), findsOneWidget);
      expect(save().onPressed, isNotNull);
    });

    testWidgets('the map search waits for a pause in typing, not Enter', (
      tester,
    ) async {
      final searched = <String>[];
      await _openFlow(tester, phoneVerified: true, searched: searched);
      await _tap(tester, 'Lanjut');
      final box = find.widgetWithText(
        TextField,
        'Cari jalan, gedung, atau kecamatan',
      );

      // Each keystroke restarts the wait; nothing goes out mid-word.
      await tester.enterText(box, 'Ij');
      await tester.pump(const Duration(seconds: 3));
      expect(searched, isEmpty, reason: 'under 3 characters');
      await tester.enterText(box, 'Ije');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(box, 'Ijen');
      await tester.pump(const Duration(seconds: 1));
      expect(searched, isEmpty);
      // The wait already shows as working.
      final spinner = find.descendant(
        of: find.ancestor(of: box, matching: find.byType(Row)).first,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(spinner, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(searched, ['Ijen']);
      await tester.pump();
      expect(find.text('Ijen Boulevard, Klojen, Kota Malang'), findsOneWidget);
      expect(spinner, findsNothing);

      // The same text again is not asked twice.
      await tester.enterText(box, 'Ijen ');
      await tester.pump(const Duration(seconds: 3));
      expect(searched, ['Ijen']);

      // Picking one closes the list.
      await tester.tap(find.text('Jalan Ijen, Klojen, Kota Malang'));
      await tester.pumpAndSettle();
      expect(find.text('Ijen Boulevard, Klojen, Kota Malang'), findsNothing);
    });

    testWidgets('opens the store in one write, and shows it', (tester) async {
      final harness = await _openFlow(tester, phoneVerified: true);
      await tester.enterText(find.byType(TextField), 'Binder Mulyana');
      await tester.pumpAndSettle();
      await _tap(tester, 'Lanjut');
      await _pickupAtIjen(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Rumah pagar hitam'),
        'Pagar hitam',
      );
      await _tap(tester, 'Simpan alamat');

      expect(find.text('kirim kartumu.'), findsOneWidget);
      expect(find.text('Rekomendasi'), findsOneWidget);
      for (final chip in ['JNE', 'J&T', 'Gojek']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      expect(find.text('Lion Express'), findsNothing);
      // Nothing on the server yet.
      expect(harness.store.opened, isEmpty);

      await _tap(tester, 'Buka toko');
      final opened = harness.store.opened.single;
      expect(opened['name'], 'Binder Mulyana');
      expect(opened['slug'], 'binder-mulyana');
      expect(opened['couriers'], [
        'gojek/instant',
        'jne/reg',
        'jne/yes',
        'jnt/ez',
      ]);
      final pickup = opened['pickup']! as Map<String, dynamic>;
      expect(pickup['contact_name'], 'mulyana');
      expect(pickup['contact_phone'], '+6281299998888');
      expect(pickup['city_name'], 'Kota Malang');
      expect(pickup['district'], 'Klojen');
      expect(pickup['full_address'], 'Jl. Ijen No. 25');
      expect(pickup['notes'], 'Pagar hitam');
      expect(pickup['pickup_lat'], _here.latitude);
      // And the address for buying, ticked by default.
      expect(harness.addresses.created, [
        'Jl. Ijen No. 25, Klojen, Kota Malang',
      ]);

      expect(find.text('sudah buka!'), findsOneWidget);
      // The finished store has its own close button, and no step header.
      expect(find.byType(CoretanStepHeader), findsNothing);
      expect(find.text('Binder Mulyana'), findsOneWidget);
      expect(find.text('oleh @mulyana'), findsOneWidget);
      expect(find.text('BM'), findsOneWidget);
      expect(find.text('0812 •••• 8888'), findsOneWidget);
      expect(find.text('3 kurir aktif'), findsOneWidget);
      expect(find.text('Jual kartu pertama'), findsOneWidget);

      // Closing goes to the Jual tab, which is now the dashboard.
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('dasbor'), findsOneWidget);
    });

    testWidgets('a store that fails to open says why, and stays', (
      tester,
    ) async {
      await _openFlow(
        tester,
        phoneVerified: true,
        openError: 'URL toko itu baru saja dipakai orang lain. Coba lagi.',
      );
      await _tap(tester, 'Lanjut');
      await _pickupAtIjen(tester);
      await _tap(tester, 'Simpan alamat');
      await _tap(tester, 'Buka toko');

      expect(
        find.text('URL toko itu baru saja dipakai orang lain. Coba lagi.'),
        findsOneWidget,
      );
      expect(find.text('sudah buka!'), findsNothing);
    });

    testWidgets('couriers by hand start from the recommendation', (
      tester,
    ) async {
      final harness = await _openFlow(tester, phoneVerified: true);
      await _tap(tester, 'Lanjut');
      await _pickupAtIjen(tester);
      await _tap(tester, 'Simpan alamat');

      await _tap(tester, 'Atur manual');
      expect(
        find.text('4 layanan dipilih · ubah di langkah berikut'),
        findsOneWidget,
      );
      // Picking by hand is a screen of its own.
      await _tap(tester, 'Pilih layanan kurir');
      expect(find.text('kurir kamu.'), findsOneWidget);
      expect(find.text('4 dari 5 layanan dipilih'), findsOneWidget);
      // Drop Gojek, add AnterAja.
      await _tap(tester, 'Gojek · INSTANT');
      await _tap(tester, 'AnterAja · REG');
      expect(find.text('4 dari 5 layanan dipilih'), findsOneWidget);
      // Nothing written until the store opens.
      expect(harness.store.opened, isEmpty);
      await _tap(tester, 'Buka toko · 4 layanan');

      expect((harness.store.opened.single['couriers']! as List).toSet(), {
        'jne/reg',
        'jne/yes',
        'jnt/ez',
        'anteraja/reg',
      });
      expect(find.text('4 layanan kurir aktif'), findsOneWidget);
      expect(find.text('JNE, J&T Express, AnterAja'), findsOneWidget);
    });

    testWidgets('no courier, no store: the button says why', (tester) async {
      await _openFlow(tester, phoneVerified: true);
      await _tap(tester, 'Lanjut');
      await _pickupAtIjen(tester);
      await _tap(tester, 'Simpan alamat');
      await _tap(tester, 'Atur manual');
      await _tap(tester, 'Pilih layanan kurir');

      await _tap(tester, 'Pilih semua');
      expect(find.text('5 dari 5 layanan dipilih'), findsOneWidget);
      await _tap(tester, 'Kosongkan');
      expect(find.text('0 dari 5 layanan dipilih'), findsOneWidget);
      expect(find.text('Pilih minimal 1 layanan kurir.'), findsOneWidget);
      final open = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Buka toko · 0 layanan'),
      );
      expect(open.onPressed, isNull);

      // Back to the choice, and the recommendation is still one tap away.
      await tester.tap(find.bySemanticsLabel('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('kirim kartumu.'), findsOneWidget);
    });

    testWidgets('a profile put off says so on the finished store', (
      tester,
    ) async {
      await _openFlow(tester, phoneVerified: true);
      await _tap(tester, 'Nanti dulu');
      await _pickupAtIjen(tester);
      await _tap(tester, 'Simpan alamat');
      await _tap(tester, 'Buka toko');

      expect(find.text('Profil toko pakai default'), findsOneWidget);
      expect(
        find.text('Nama toko: mulyana · bisa diubah nanti'),
        findsOneWidget,
      );
      expect(find.text('selesai'), findsNWidgets(4));
    });
  });

  group('the Kurir settings', () {
    testWidgets('the same list as Buka Toko, saved as a whole', (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      _stillMotion(tester);
      final store = _FakeStoreRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            storeProfileRepositoryProvider.overrideWithValue(store),
            storeProfileProvider.overrideWith(
              (ref) async => const StoreProfile(
                storeName: 'Binder Mulyana',
                acceptedCourierServices: ['jne/reg', 'gojek/instant'],
              ),
            ),
            courierServicesProvider.overrideWith((ref) async => _catalog),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SellerCouriersPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // What the store takes now, ticked; the speeds as cards.
      expect(find.text('2 dari 5 layanan dipilih'), findsOneWidget);
      expect(find.text('Instan (1–3 jam)'), findsOneWidget);
      expect(find.text('Reguler'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);

      await _tap(tester, 'J&T Express · EZ');
      expect(find.text('3 dari 5 layanan dipilih'), findsOneWidget);
      await _tap(tester, 'Simpan');
      expect(store.savedCouriers.single.toSet(), {
        'jne/reg',
        'gojek/instant',
        'jnt/ez',
      });
    });
  });

  group('with motion', () {
    // The rest of this file holds still; these let everything move, and
    // walk time forward by hand, since the drawings never settle.
    Future<void> step(WidgetTester tester, [int ms = 700]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('the launcher draws itself in, and keeps moving', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // The test bundle reads assets with real file I/O, which the fake
      // clock doesn't drive; loaded once in real time, every drawing after
      // finds the data ready.
      ScribbleData.clearCache();
      await tester.runAsync(
        () => ScribbleData.load(
          'toko_lapak',
        ).timeout(const Duration(seconds: 10)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            privateProfileProvider.overrideWith(
              (ref) async => const PrivateProfile(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: StoreSetupLauncher()),
          ),
        ),
      );
      // The data was finished in real time, so the drawings hear of it
      // there too.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await step(tester, 3000);
      expect(
        find.descendant(
          of: find.byType(ScribbleDrawing),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      expect(find.text('0% potongan.'), findsOneWidget);
      // The stall's idle loop is still running: it never settles.
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a full code waits a beat, then the boxes go green', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final otp = _FakeOtp();
      final router = GoRouter(
        initialLocation: Routes.openStore,
        routes: [
          GoRoute(
            path: Routes.openStore,
            builder: (_, __) => const StoreSetupPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            privateProfileProvider.overrideWith(
              (ref) async => const PrivateProfile(),
            ),
            storeProfileRepositoryProvider.overrideWithValue(_FakeStoreRepo()),
            areaCatalogProvider.overrideWith((ref) async => _areas),
            addressesProvider.overrideWith((ref) async => const []),
            phoneOtpRepositoryProvider.overrideWithValue(otp),
            courierServicesProvider.overrideWith((ref) async => _catalog),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await step(tester);
      final header = tester.element(find.byType(CoretanStepHeader));
      await tester.tap(find.text('Nanti dulu'));
      await tester.pump(const Duration(milliseconds: 150));
      // Mid-change: one page, one header, and both steps' content while
      // one gives way to the other.
      expect(find.byType(CoretanStepHeader), findsOneWidget);
      expect(find.text('Kenalin'), findsOneWidget);
      expect(find.text('kamu berapa?'), findsOneWidget);
      await step(tester);
      // The same header, kept rather than built again, now reading 2/4.
      expect(tester.element(find.byType(CoretanStepHeader)), same(header));
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('Kenalin'), findsNothing);
      await tester.enterText(find.byType(TextField), '81234567890');
      await step(tester, 300);
      await tester.tap(find.text('Kirim kode via WhatsApp'));
      await step(tester);
      expect(find.text('kode 6 digit.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 200));
      // Not yet: the last digit is seen landing first.
      expect(find.text('Nomor HP terverifikasi'), findsNothing);
      await step(tester, 400);
      expect(find.text('Nomor HP terverifikasi'), findsOneWidget);
      expect(find.text('kode 6 digit.'), findsOneWidget);
      // Then on to the pickup point.
      await step(tester, 1400);
      expect(find.text('Kartu dijemput'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
