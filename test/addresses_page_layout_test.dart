import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/account/presentation/addresses_page.dart';
import 'package:pokepedia_mobile/features/account/repository/models/address_model.dart';
import 'package:pokepedia_mobile/features/account/usecase/address_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/store_profile.dart';
import 'package:pokepedia_mobile/features/seller/usecase/store_profile_notifier.dart';

/// Web's Alamat tab is two cards: the buyer's address book over the seller's
/// pickup point. Mobile had only the first, under a different heading.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'user-1', email: 'ash@pokepedia.id');
}

AddressModel _address() => AddressModel(
  id: 1,
  slug: 'rumah',
  label: 'Rumah',
  contactName: 'Ash',
  contactPhone: '0812',
  provinceId: '31',
  provinceName: 'DKI Jakarta',
  cityId: '3171',
  cityName: 'Jakarta Selatan',
  districtId: '317101',
  district: 'Menteng',
  fullAddress: 'Jl. Pallet 1',
  isPrimary: true,
);

Widget _host({
  List<AddressModel> addresses = const [],
  StoreProfile? profile,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      addressesProvider.overrideWith((ref) async => addresses),
      storeProfileProvider.overrideWith((ref) async => profile),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const AddressesPage()),
  );
}

void main() {
  testWidgets('shows both of web\'s cards', (tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Alamat Pengiriman'), findsOneWidget);
    expect(
      find.text('Kelola alamat tujuan pengiriman pembelian kartu kamu.'),
      findsOneWidget,
    );
    expect(find.text('Alamat Pickup Toko'), findsOneWidget);
    expect(
      find.text('Titik jemput kurir untuk semua listing yang kamu jual.'),
      findsOneWidget,
    );
  });

  testWidgets('empty address book offers the dashed add button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Tambah Alamat Baru'), findsOneWidget);
    expect(find.text('Belum ada alamat tersimpan'), findsOneWidget);
    // Web only offers the search once there is something to filter.
    expect(find.text('Cari nama, kota, atau kecamatan'), findsNothing);
  });

  testWidgets('a saved address brings out the search box', (tester) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(addresses: [_address()]));
    await tester.pumpAndSettle();

    expect(find.text('Cari nama, kota, atau kecamatan'), findsOneWidget);
    expect(find.text('Rumah'), findsOneWidget);
    expect(find.text('Belum ada alamat tersimpan'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'bandung');
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada alamat cocok'), findsOneWidget);
    expect(find.text('Rumah'), findsNothing);
  });

  testWidgets('a seller without a pickup point is nudged to set one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(profile: const StoreProfile()));
    // Not pumpAndSettle: the pickup form loads the bundled area catalog and
    // keeps a loader turning, so the tree never goes quiet under test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Belum punya alamat pickup'), findsOneWidget);
  });
}
