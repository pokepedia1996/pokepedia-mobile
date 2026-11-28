import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/config/app_config.dart';
import 'package:pokepedia_mobile/features/referral/usecase/pending_referral.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An invite link (`www.pokepedia.id/r/<code>`) opens the app and leaves its
/// code for onboarding, which fills the referral field with it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => PendingReferral.code.value = null);

  group('codeFromLink', () {
    String? code(String url) => PendingReferral.codeFromLink(Uri.parse(url));

    test('reads the code, in upper case', () {
      expect(code('https://www.pokepedia.id/r/USER1266'), 'USER1266');
      expect(code('https://www.pokepedia.id/r/satos728'), 'SATOS728');
      expect(code('https://pokepedia.id/r/SATOS728/'), 'SATOS728');
    });

    test('takes the app\'s own scheme, for trying invites locally', () {
      expect(code('id.pokepedia.app://r/USER1266'), 'USER1266');
      expect(code('id.pokepedia.app://r/user1266/'), 'USER1266');
      expect(code('id.pokepedia.app://login-callback/USER1266'), isNull);
      expect(code('other.app://r/USER1266'), isNull);
    });

    test('takes the website this build talks to (APP_URL)', () {
      // No APP_URL under `flutter test`: AppConfig falls back to the local
      // stack, as a debug run without env.json does.
      final local = Uri.parse(AppConfig.appUrl);
      expect(code(local.replace(path: '/r/USER1266').toString()), 'USER1266');
    });

    test('ignores anything that is not an invite link', () {
      expect(code('https://www.pokepedia.id/auth/confirm?type=signup'), isNull);
      expect(code('https://www.pokepedia.id/r/'), isNull);
      expect(code('https://www.pokepedia.id/r/AB'), isNull);
      expect(code('https://www.pokepedia.id/r/SATOS728/extra'), isNull);
      expect(code('https://evil.example/r/SATOS728'), isNull);
    });
  });

  test('a saved code survives a restart, and clearing drops it', () async {
    await PendingReferral.save('SATOS728');
    PendingReferral.code.value = null;
    await PendingReferral.load();
    expect(PendingReferral.code.value, 'SATOS728');

    await PendingReferral.clear();
    await PendingReferral.load();
    expect(PendingReferral.code.value, isNull);
  });
}
