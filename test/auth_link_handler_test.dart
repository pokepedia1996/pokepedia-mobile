import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_link_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The emailed links are App Links so the *app* redeems them: signup runs
/// under PKCE, so the code verifier lives on this device and the website
/// cannot complete the exchange for a signup that started here.
class _FakeAuth implements GoTrueClient {
  final calls = <({String hash, OtpType type})>[];
  Object? throwOnVerify;

  @override
  Future<AuthResponse> verifyOTP({
    String? email,
    String? phone,
    String? token,
    required OtpType type,
    String? redirectTo,
    String? captchaToken,
    String? tokenHash,
  }) async {
    calls.add((hash: tokenHash ?? '', type: type));
    final failure = throwOnVerify;
    if (failure != null) throw failure;
    return AuthResponse();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements SupabaseClient {
  _FakeClient(this._auth);
  final GoTrueClient _auth;

  @override
  GoTrueClient get auth => _auth;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uri _link({
  String host = 'www.pokepedia.id',
  String path = '/auth/confirm',
  String? hash = 'pkce_abc123',
  String? type = 'signup',
}) {
  return Uri.https(host, path, {
    if (hash != null) 'token_hash': hash,
    if (type != null) 'type': type,
    'next': '/login',
  });
}

void main() {
  late _FakeAuth auth;
  late AuthLinkHandler handler;

  setUp(() {
    auth = _FakeAuth();
    handler = AuthLinkHandler(_FakeClient(auth));
  });

  test('redeems a signup link with its token hash', () async {
    expect(await handler.handle(_link()), OtpType.signup);
    expect(auth.calls.single.hash, 'pkce_abc123');
    expect(auth.calls.single.type, OtpType.signup);
  });

  test('maps every type the website also honours', () async {
    for (final entry in {
      'signup': OtpType.signup,
      'recovery': OtpType.recovery,
      'invite': OtpType.invite,
      'email': OtpType.email,
      'magiclink': OtpType.magiclink,
    }.entries) {
      expect(await handler.handle(_link(type: entry.key)), entry.value);
    }
  });

  test('accepts the apex host as well as www', () async {
    // App Links do not follow redirects, so both are claimed; a link that
    // arrives on either must redeem.
    expect(await handler.handle(_link(host: 'pokepedia.id')), OtpType.signup);
  });

  test('ignores a link from a host we never claimed', () async {
    // Belt and braces over the manifest: a link reaching this handler by any
    // other route is not trusted with a token.
    expect(await handler.handle(_link(host: 'evil.example.com')), isNull);
    expect(auth.calls, isEmpty);
  });

  test('ignores a link for another path', () async {
    // The intent filter is scoped to /auth/confirm, but a stray link must
    // fall through quietly rather than be redeemed as an auth callback.
    expect(await handler.handle(_link(path: '/market')), isNull);
    expect(auth.calls, isEmpty);
  });

  test('ignores a link with no token or an unknown type', () async {
    expect(await handler.handle(_link(hash: null)), isNull);
    expect(await handler.handle(_link(hash: '')), isNull);
    expect(await handler.handle(_link(type: 'nonsense')), isNull);
    expect(await handler.handle(_link(type: null)), isNull);
    expect(auth.calls, isEmpty);
  });

  test('a used or expired link fails without throwing', () async {
    // Tapping the same link twice is ordinary, not exceptional: the session
    // is unchanged and the user stays where they were.
    auth.throwOnVerify = const AuthException('Token has expired');
    expect(await handler.handle(_link()), isNull);
    expect(auth.calls, hasLength(1));
  });
}
