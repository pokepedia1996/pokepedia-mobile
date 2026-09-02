import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/features/scanner/usecase/scanner_notifier.dart';

void main() {
  group('ApiRateLimitedException', () {
    test('is an ApiException, so existing handlers still catch it', () {
      const e = ApiRateLimitedException('Terlalu banyak permintaan');
      expect(e, isA<ApiException>());
      expect(e.statusCode, 429);
    });

    test('is not an auth failure', () {
      // Catching it as one would send the user to the login screen for
      // being too quick.
      const e = ApiRateLimitedException('Terlalu banyak permintaan');
      expect(e, isNot(isA<ApiAuthException>()));
    });

    test('carries the wait when the server gave one', () {
      const e = ApiRateLimitedException(
        'Terlalu banyak permintaan',
        retryAfter: Duration(seconds: 60),
      );
      expect(e.retryAfter, const Duration(seconds: 60));
    });

    test('a wait is optional — the embedder shape may omit it', () {
      const e = ApiRateLimitedException('Server pindai sedang sibuk');
      expect(e.retryAfter, isNull);
    });
  });

  group('ScanFailed', () {
    test('a plain failure asks for no particular wait', () {
      const failed = ScanFailed('Kartu tidak dikenali, pindai ulang');
      expect(failed.retryAfter, isNull);
    });

    test(
      'a rate-limited failure carries the server\'s wait to the shutter',
      () {
        // Re-arming on the usual ~900ms cooldown would spend another token
        // against a budget the server just said was empty.
        const failed = ScanFailed(
          'Terlalu banyak permintaan',
          retryAfter: Duration(seconds: 60),
        );
        expect(failed.retryAfter, const Duration(seconds: 60));
      },
    );
  });

  group('re-arm jitter', () {
    // Mirrors `_scheduleRearm`: base delay plus up to 40% at random. The
    // point is that many phones scanning at once do not re-arm in lockstep
    // and arrive at the embedder in a wave.
    Duration jittered(Duration base, double roll) =>
        base +
        Duration(milliseconds: (base.inMilliseconds * 0.4 * roll).round());

    test('never shortens the cooldown', () {
      const base = Duration(milliseconds: 900);
      for (final roll in [0.0, 0.5, 1.0]) {
        expect(jittered(base, roll) >= base, isTrue, reason: '$roll');
      }
    });

    test('spreads across a 40% band', () {
      const base = Duration(milliseconds: 900);
      expect(jittered(base, 0), const Duration(milliseconds: 900));
      expect(jittered(base, 1), const Duration(milliseconds: 1260));
    });

    test('scales with a server-requested wait rather than replacing it', () {
      // A 60s budget refusal still gets jittered, for the same reason the
      // 900ms cooldown does — everyone refused at once retries at once.
      const base = Duration(seconds: 60);
      expect(jittered(base, 0) >= base, isTrue);
      expect(jittered(base, 1), const Duration(seconds: 84));
    });
  });
}
