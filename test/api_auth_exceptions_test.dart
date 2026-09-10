import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';

/// Two different failures wear the same 401, and the app's advice has to
/// differ: a refresh that was refused means sign in again, while a *fresh*
/// token being refused means the server is not reading the token at all —
/// signing in again cannot fix that, and telling the user to is what made
/// `/api/scan` say "sesi telah habis" seconds after login.
void main() {
  test('a refused fresh token is not an expired session', () {
    const refused = ApiAuthRefusedException();
    expect(refused, isNot(isA<ApiSessionExpiredException>()));
    // Callers that sign the user out key off the expired type; this one must
    // fall through to their generic handler instead.
    expect(refused, isA<ApiAuthException>());
    expect(refused, isA<ApiException>());
  });

  test('an expired session still asks for a new sign-in', () {
    const expired = ApiSessionExpiredException();
    expect(expired, isA<ApiAuthException>());
    expect(expired.message.toLowerCase(), contains('masuk lagi'));
  });

  test('the refused message does not send the user to the login screen', () {
    const refused = ApiAuthRefusedException();
    expect(refused.message, isNot(matches(RegExp(r'^Sesi kamu sudah'))));
    expect(refused.message.toLowerCase(), contains('server menolak'));
  });
}
