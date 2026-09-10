import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../utils/image_url.dart';
import 'supabase_provider.dart';

/// Bounds every auth network call so a stalled connection surfaces as an
/// error instead of leaving the caller's loading state stuck forever.
const _authTimeout = Duration(seconds: 15);

/// The ceiling on a step the *user* is driving — Apple's sign-in sheet, where
/// they read a consent screen, pass Face ID and choose whether to hide their
/// email. [_authTimeout] is a network budget and far too short for that: at
/// 15 seconds it cancelled people mid-authentication and reported a
/// connection problem. Long enough that no real person hits it, short enough
/// that a sheet which never returns still releases the button.
const _interactiveTimeout = Duration(minutes: 3);

/// Scopes asked for alongside sign-in. `email` and `profile` are what
/// Supabase needs to populate the user record.
const _googleScopes = <String>['email', 'profile'];

/// The signed-in user, combining `auth.users` (session) with `profiles`
/// (username).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.username,
    this.avatarUrl,
    this.isAdmin = false,
  });

  final String id;
  final String email;
  final String? username;

  /// `profiles.avatar_url`, shown by the account header and settings.
  final String? avatarUrl;

  /// `profiles.role == 'admin'` — web renders an admin's name in gold.
  final bool isAdmin;
}

enum SignUpOutcome { signedIn, needsEmailConfirmation, error }

class SignUpResult {
  const SignUpResult(this.outcome, {this.errorMessage});

  final SignUpOutcome outcome;
  final String? errorMessage;
}

/// Session-driven auth state, mirroring
/// `pokepedia-web/components/auth/auth-provider.tsx` but backed by
/// `supabase_flutter`'s local session persistence instead of cookies.
class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final client = ref.watch(supabaseClientProvider);

    // `onAuthStateChange` is a BehaviorSubject under the hood — it replays
    // the *current* state to every new subscriber immediately. Since this
    // subscription is recreated on every rebuild, reacting to that replay
    // would re-invalidate forever (subscribe → replay → invalidate →
    // rebuild → resubscribe → replay → ...). Only genuinely new events
    // (received after this subscription's own initial replay) should
    // trigger a refresh.
    var skippedReplay = false;
    final sub = client.auth.onAuthStateChange.listen((_) {
      if (!skippedReplay) {
        skippedReplay = true;
        return;
      }
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);
    return _load(client);
  }

  Future<AppUser?> _load(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    String? username;
    String? avatarUrl;
    var isAdmin = false;
    try {
      final profile = await client
          .from('profiles')
          .select('username, avatar_url, role')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_authTimeout);
      username = profile?['username'] as String?;
      avatarUrl = proxyImageUrl(profile?['avatar_url'] as String?);
      isAdmin = profile?['role'] == 'admin';
    } catch (_) {
      // A failed profile lookup shouldn't block showing the signed-in state.
    }
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      username: username,
      avatarUrl: avatarUrl,
      isAdmin: isAdmin,
    );
  }

  Future<String?> signIn(String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(_authTimeout);
      // Refresh in the background — the session is already established, so
      // the caller shouldn't block on the secondary `profiles` lookup too.
      ref.invalidateSelf();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } on TimeoutException {
      return 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.';
    }
  }

  /// Signs in with Google through the platform's own account picker.
  ///
  /// Deliberately not `signInWithOAuth`: that hands a URL to a browser and
  /// waits for a redirect to come back through a deep link, which means App
  /// Links or a custom scheme, and on a failed verification the PKCE
  /// exchange strands the session in the browser. This asks the OS for an ID
  /// token directly and trades it with Supabase — no browser, no redirect,
  /// nothing to verify.
  ///
  /// Returns whether a session was established, plus a message when
  /// something went wrong. A user who backs out of the sheet gets neither:
  /// cancelling is not an error to report.
  Future<({bool signedIn, String? error})> signInWithGoogle() async {
    if (!await _isProviderEnabled('google')) {
      // Returned raw so the single translation table renders it.
      return (
        signedIn: false,
        error: 'Unsupported provider: provider is not enabled',
      );
    }
    if (AppConfig.googleServerClientId.isEmpty) {
      return (
        signedIn: false,
        error: 'Google Sign-In belum dikonfigurasi di aplikasi ini.',
      );
    }

    final google = GoogleSignIn.instance;
    try {
      // `initialize` is documented as exactly-once, but it is idempotent and
      // cheap, and doing it here keeps the credentials next to their use.
      await google.initialize(
        // iOS only. Android identifies the app by package name and signing
        // fingerprint instead — `google_sign_in_android` documents that
        // "the clientId parameter is not supported on Android" and drops
        // it, so sending one there is at best noise and at worst a wrong
        // value someone later mistakes for the cause of a failure.
        clientId: Platform.isIOS && AppConfig.googleIosClientId.isNotEmpty
            ? AppConfig.googleIosClientId
            : null,
        // The web client id, which is what Supabase verifies the ID token's
        // audience against.
        serverClientId: AppConfig.googleServerClientId,
      );

      if (!google.supportsAuthenticate()) {
        return (
          signedIn: false,
          error: 'Masuk dengan Google tidak didukung di perangkat ini.',
        );
      }

      // Same interactive budget as Apple's sheet. Left unbounded, a picker
      // that never returns leaves the button spinning for good.
      final GoogleSignInAccount account;
      try {
        account = await google
            .authenticate(scopeHint: _googleScopes)
            .timeout(_interactiveTimeout);
      } on TimeoutException {
        return (
          signedIn: false,
          error: 'Proses masuk dengan Google tidak selesai. Coba lagi.',
        );
      }
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return (
          signedIn: false,
          error: 'Google tidak mengembalikan token identitas.',
        );
      }

      // Supabase accepts the access token as well, which lets it read the
      // profile fields the ID token doesn't carry.
      final authorization =
          await account.authorizationClient.authorizationForScopes(
            _googleScopes,
          ) ??
          await account.authorizationClient.authorizeScopes(_googleScopes);

      final client = ref.read(supabaseClientProvider);
      await client.auth
          .signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: authorization.accessToken,
          )
          .timeout(_authTimeout);

      ref.invalidateSelf();
      return (signedIn: true, error: null);
    } on GoogleSignInException catch (e) {
      // Backing out of the sheet is a decision, not a failure.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return (signedIn: false, error: null);
      }
      return (signedIn: false, error: e.description ?? e.code.name);
    } on AuthException catch (e) {
      return (signedIn: false, error: e.message);
    } on TimeoutException {
      return (
        signedIn: false,
        error: 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.',
      );
    }
  }

  /// Signs in with Apple through the system sheet. iOS only.
  ///
  /// Apple's button is a platform requirement rather than a preference: an
  /// iOS app offering a third-party social login has to offer this too
  /// (App Store guideline 4.8). There is no Android equivalent here — Apple's
  /// Android flow is a web redirect, which is the browser hand-off this app
  /// deliberately moved away from for Google.
  ///
  /// The nonce is sent hashed to Apple and raw to Supabase: Apple embeds the
  /// SHA-256 in the ID token, and Supabase re-hashes the raw value to check
  /// the token was minted for this request and not replayed.
  Future<({bool signedIn, String? error})> signInWithApple() async {
    if (!Platform.isIOS) {
      return (
        signedIn: false,
        error: 'Masuk dengan Apple hanya tersedia di iOS.',
      );
    }
    if (!await _isProviderEnabled('apple')) {
      // Returned raw so the single translation table renders it.
      return (
        signedIn: false,
        error: 'Unsupported provider: provider is not enabled',
      );
    }
    if (!await SignInWithApple.isAvailable()) {
      return (
        signedIn: false,
        error: 'Masuk dengan Apple tidak didukung di perangkat ini.',
      );
    }

    final rawNonce = _randomNonce();
    try {
      final AuthorizationCredentialAppleID credential;
      try {
        credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
        ).timeout(_interactiveTimeout);
      } on TimeoutException {
        // Distinct from the network one below: nothing was wrong with the
        // connection, the sheet just never came back.
        return (
          signedIn: false,
          error: 'Proses masuk dengan Apple tidak selesai. Coba lagi.',
        );
      }

      final idToken = credential.identityToken;
      if (idToken == null) {
        return (
          signedIn: false,
          error: 'Apple tidak mengembalikan token identitas.',
        );
      }

      final client = ref.read(supabaseClientProvider);
      await client.auth
          .signInWithIdToken(
            provider: OAuthProvider.apple,
            idToken: idToken,
            nonce: rawNonce,
          )
          .timeout(_authTimeout);

      ref.invalidateSelf();
      return (signedIn: true, error: null);
    } on SignInWithAppleAuthorizationException catch (e) {
      // Dismissing the sheet is a decision, not a failure — the same way
      // backing out of Google's account picker is treated.
      if (e.code == AuthorizationErrorCode.canceled) {
        return (signedIn: false, error: null);
      }
      return (signedIn: false, error: e.message);
    } on SignInWithAppleException catch (e) {
      return (signedIn: false, error: e.toString());
    } on AuthException catch (e) {
      return (signedIn: false, error: e.message);
    } on TimeoutException {
      return (
        signedIn: false,
        error: 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.',
      );
    }
  }

  /// A URL-safe random string for the sign-in nonce.
  String _randomNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Whether the project has [provider] turned on.
  ///
  /// Supabase rejects `signInWithIdToken` for a disabled provider, and the
  /// raw message is not something to show a user. Asking first turns it into
  /// a sentence — and costs one small request only on a social path.
  ///
  /// Fails open: if the check itself can't complete, sign-in proceeds rather
  /// than being blocked by a flaky probe.
  Future<bool> _isProviderEnabled(String provider) async {
    final client = HttpClient()..connectionTimeout = _authTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse('${AppConfig.supabaseUrl}/auth/v1/settings'))
          .timeout(_authTimeout);
      request.headers.set('apikey', AppConfig.supabaseAnonKey);
      final response = await request.close().timeout(_authTimeout);
      if (response.statusCode != 200) return true;
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      final external = body is Map ? body['external'] : null;
      if (external is! Map) return true;
      return external[provider] == true;
    } catch (_) {
      return true;
    } finally {
      client.close(force: true);
    }
  }

  Future<SignUpResult> signUp(
    String username,
    String email,
    String password,
  ) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final response = await client.auth
          .signUp(email: email, password: password)
          .timeout(_authTimeout);
      if (response.session == null) {
        // Email confirmation required (production config) — no session yet.
        return const SignUpResult(SignUpOutcome.needsEmailConfirmation);
      }
      // `handle_new_user` already inserted a bare `profiles` row (trigger,
      // server-side); persist the chosen username onto it now that we
      // have a session to satisfy RLS.
      try {
        await client
            .from('profiles')
            .update({'username': username})
            .eq('id', response.user!.id)
            .timeout(_authTimeout);
      } catch (_) {
        // Username format/uniqueness conflicts shouldn't block sign-up —
        // it can be set later from account settings.
      }
      ref.invalidateSelf();
      return const SignUpResult(SignUpOutcome.signedIn);
    } on AuthException catch (e) {
      return SignUpResult(SignUpOutcome.error, errorMessage: e.message);
    } on TimeoutException {
      return const SignUpResult(
        SignUpOutcome.error,
        errorMessage:
            'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.',
      );
    }
  }

  Future<void> signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut().timeout(_authTimeout);
  }

  /// Fire-and-forget like web's `resetPasswordForEmail` call — always
  /// succeeds from the caller's perspective so it doesn't leak whether an
  /// email exists in the system.
  Future<String?> requestPasswordReset(String email) async {
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .resetPasswordForEmail(email)
          .timeout(_authTimeout);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } on TimeoutException {
      return 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.';
    }
  }

  Future<String?> updatePassword(String password) async {
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .updateUser(UserAttributes(password: password))
          .timeout(_authTimeout);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } on TimeoutException {
      return 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.';
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
