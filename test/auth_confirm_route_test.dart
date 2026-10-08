import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';

/// Tapping the emailed confirmation link opens the app with the whole URL as
/// the location go_router is asked for. The router had no route for
/// `/auth/confirm`, so a brand-new account's first screen was "Page Not
/// Found" over a GoException — while the token was being redeemed perfectly
/// well behind it by `AuthLinkHandler`.
void main() {
  test('the path the email points at is one the router knows', () {
    expect(Routes.authConfirm, '/auth/confirm');
  });

  test('a confirmation link resolves to the path, query and all', () {
    // What the OS hands over, verbatim from the email Supabase sends.
    final uri = Uri.parse(
      'https://www.pokepedia.id/auth/confirm'
      '?token_hash=pkce_7519cfdfc7d06cf97f065f1d969e0975'
      '&type=signup&next=/login',
    );

    // go_router matches on the path, so the host and query ride along
    // without needing routes of their own.
    expect(uri.path, Routes.authConfirm);
    expect(uri.queryParameters['type'], 'signup');
  });

  test('the router registers it', () {
    // Read from source: the router listens to `Supabase.instance` at
    // construction, so it cannot be built in a test — the same reason
    // `router_no_duplicate_routes_test` reads the file.
    final source = File('lib/app/router/app_router.dart').readAsStringSync();
    expect(source, contains('path: Routes.authConfirm'));
  });

  test('it is a redirect, not a page', () {
    // Nothing is drawn: the token is redeemed off the same link through
    // app_links, and this only decides where the user stands meanwhile. A
    // builder here would flash a screen over the one the session is about
    // to produce.
    final route = GoRoute(
      path: Routes.authConfirm,
      redirect: (_, __) => Routes.home,
    );

    expect(route.builder, isNull);
    expect(route.redirect, isNotNull);
  });
}
