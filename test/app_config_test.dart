import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/config/app_config.dart';

void main() {
  group('AppConfig.appUrl', () {
    test('has no trailing slash, since paths are concatenated raw', () {
      // `'${AppConfig.appUrl}$path'` with a trailing slash would build
      // `//api/...`, which resolves to a different origin entirely.
      expect(AppConfig.appUrl.endsWith('/'), isFalse);
    });

    test('never points at the apex host', () {
      // The apex answers every request with a 308 to `www`, and Dart's
      // HttpClient only auto-follows redirects for GET and HEAD. Posting to
      // the apex therefore returns the redirect body instead of the route's
      // — which is how checkout stopped creating invoices while still
      // looking like it had returned a payload.
      //
      // Asserted as a rule rather than a literal so the suite still passes
      // under `--dart-define=APP_URL=...` for local development.
      expect(AppConfig.appUrl, isNot('https://pokepedia.id'));
      expect(AppConfig.appUrl.startsWith('https://pokepedia.id/'), isFalse);
    });

    test('debug builds default to a local dev server', () {
      // Tests run in debug, so with no APP_URL override this is the local
      // default — the point being that a debug build never silently talks to
      // production.
      const override = String.fromEnvironment('APP_URL');
      if (override.isEmpty) {
        expect(AppConfig.isLocalApi, isTrue);
        expect(AppConfig.appUrl, startsWith('http://'));
      } else {
        expect(AppConfig.appUrl, override);
      }
    });

    test(
      'the local host is reachable from a device, not the device itself',
      () {
        // `localhost` on Android is the phone; `10.0.2.2` is the emulator's
        // alias for the host machine. Getting this wrong is a connection
        // refused that reads like a server fault.
        const override = String.fromEnvironment('APP_URL');
        if (override.isEmpty && AppConfig.isLocalApi) {
          expect(AppConfig.appUrl, isNot(contains('//localhost')));
        }
      },
      skip: !Platform.isAndroid ? 'Android-only host alias' : null,
    );
  });

  group('isLocalApi', () {
    test('tracks whether the host is the real site', () {
      // Guards the branch that skips the firewall bypass: getting this
      // backwards would stop sending the header in production, or spend a
      // pointless Edge Function round trip against a dev server.
      expect(AppConfig.isLocalApi, !AppConfig.appUrl.contains('pokepedia.id'));
    });
  });
}
