import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';

void main() {
  group('auth exception hierarchy', () {
    test('a session-expired failure is still an auth failure', () {
      // Callers that only care about "auth broke" keep working; the ones
      // that force a re-login catch the narrower type first.
      const expired = ApiSessionExpiredException();
      expect(expired, isA<ApiAuthException>());
      expect(expired, isA<ApiException>());
    });

    test('a plain auth failure is not a session-expired one', () {
      // The distinction is the whole point: a single 401 gets retried, and
      // only an unrecoverable session sends the user to the login screen.
      const plain = ApiAuthException('Sesi kamu berakhir. Masuk lagi ya.');
      expect(plain, isNot(isA<ApiSessionExpiredException>()));
    });

    test('it carries copy aimed at the user, not a status code', () {
      expect(
        const ApiSessionExpiredException().message,
        'Sesi kamu sudah berakhir. Masuk lagi untuk melanjutkan.',
      );
    });
  });

  group('refresh margin', () {
    test('a token expiring inside the margin counts as due', () {
      // Mirrors `_accessToken`: the SDK refreshes at 30s remaining, and its
      // timer is tied to app lifecycle, so a token that survives the check
      // can still die in flight.
      const margin = Duration(seconds: 30);
      final now = DateTime.now();

      bool due(DateTime expiresAt) => expiresAt.subtract(margin).isBefore(now);

      expect(due(now.add(const Duration(seconds: 10))), isTrue);
      expect(due(now.add(const Duration(seconds: 29))), isTrue);
      expect(due(now.add(const Duration(minutes: 5))), isFalse);
      // Already expired is trivially due.
      expect(due(now.subtract(const Duration(minutes: 1))), isTrue);
    });
  });
}
