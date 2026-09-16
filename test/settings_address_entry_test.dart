import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/settings/presentation/settings_page.dart';
import 'package:pokepedia_mobile/features/user/repository/models/profile_models.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';

/// Web keeps the address book behind its own "Alamat" sidebar tab. Mobile
/// had the page built and routed but nothing pointing at it, so Pengaturan
/// offered no way to manage addresses at all.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'user-1', email: 'ash@pokepedia.id');
}

Widget _host() {
  final router = GoRouter(
    initialLocation: Routes.settings,
    routes: [
      GoRoute(path: Routes.settings, builder: (_, __) => const SettingsPage()),
      GoRoute(
        path: Routes.addresses,
        builder: (_, __) => const Scaffold(body: Text('halaman alamat')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      myProfileProvider.overrideWith(
        (ref) async => const PublicProfile(
          userId: 'user-1',
          username: 'ash',
          contributionCount: 0,
        ),
      ),
      privateProfileProvider.overrideWith((ref) async => const PrivateProfile()),
      myCollectionVisibilityProvider.overrideWith(
        (ref) async => const CollectionVisibility(
          collectionId: 'col-1',
          isPublic: true,
          showQuantity: true,
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('Pengaturan offers an Alamat entry that opens the address book', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final entry = find.text('Alamat');
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('halaman alamat'), findsOneWidget);
  });

  testWidgets('heads the page with the identity card and legal links, as web '
      'does', (tester) async {
    tester.view.physicalSize = const Size(1170, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Identity card: username over the email. The name also appears in the
    // avatar/profile sections below, so only the email is unique to the card.
    expect(find.text('ash'), findsWidgets);
    expect(find.text('ash@pokepedia.id'), findsOneWidget);

    // Nav, with Profil reading as the tab this page already is.
    expect(find.text('Profil'), findsOneWidget);

    expect(find.text('LEGAL'), findsOneWidget);
    expect(find.text('Syarat & Ketentuan'), findsOneWidget);
    expect(find.text('Kebijakan Privasi'), findsOneWidget);
    expect(find.text('Panduan Kondisi Kartu'), findsOneWidget);
  });

  testWidgets('does not offer push notifications or a donation link', (
    tester,
  ) async {
    // Both are web-only on purpose.
    tester.view.physicalSize = const Size(1170, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Notifikasi Push'), findsNothing);
    expect(find.textContaining('Dukung Pengembang'), findsNothing);
  });
}
