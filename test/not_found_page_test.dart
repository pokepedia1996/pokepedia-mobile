import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/not_found_page.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';

/// A location with no page used to show go_router's raw exception. It now
/// says so in words and leads back to Beranda.
void main() {
  testWidgets('says the page is missing, without the exception', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/tidak-ada',
      errorBuilder: (_, __) => const NotFoundPage(),
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (_, __) => const Scaffold(body: Text('Beranda')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Halaman tidak ditemukan'), findsOneWidget);
    expect(find.textContaining('GoException'), findsNothing);
    expect(find.textContaining('no routes'), findsNothing);

    await tester.tap(find.text('Kembali ke Beranda'));
    await tester.pumpAndSettle();
    expect(find.text('Beranda'), findsOneWidget);
  });
}
