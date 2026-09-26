import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/utils/primary_collection.dart';
import '../config/app_config.dart';
import '../../app/router/app_router.dart';
import '../../app/router/routes.dart';
import '../utils/image_url.dart';
import 'supabase_provider.dart';
import '../errors/user_message.dart';

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
    this.onboarded,
  });

  final String id;
  final String email;
  final String? username;

  /// `profiles.avatar_url`, shown by the account header and settings.
  final String? avatarUrl;

  /// `profiles.role == 'admin'` — web renders an admin's name in gold.
  final bool isAdmin;

  /// `profiles.onboarded` — false until a username has been chosen, which is
  /// what [OnboardingModal] gates on.
  ///
  /// Null while the `profiles` row is still in flight. Deliberately not
  /// defaulted to false: the session resolves before the profile does, and a
  /// false default would flash the modal over every launch before the real
  /// answer arrived. Only an explicit false opens it.
  final bool? onboarded;
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
  /// Set when the provider is torn down, so the background profile fetch does
  /// not write state into a container that is gone.
  bool _disposed = false;

  /// Bumped on every build. `onDispose` runs before a rebuild as well as on
  /// teardown, so `_disposed` alone would let an enrichment started by the
  /// previous build write its result over the new one — a sign-out followed
  /// quickly by a sign-in could land the wrong user.
  int _generation = 0;

  @override
  FutureOr<AppUser?> build() {
    final client = ref.watch(supabaseClientProvider);
    _disposed = false;
    final generation = ++_generation;

    // `onAuthStateChange` is a BehaviorSubject under the hood — it replays
    // the *current* state to every new subscriber immediately. Since this
    // subscription is recreated on every rebuild, reacting to that replay
    // would re-invalidate forever (subscribe → replay → invalidate →
    // rebuild → resubscribe → replay → ...). Only genuinely new events
    // (received after this subscription's own initial replay) should
    // trigger a refresh.
    var skippedReplay = false;
    final sub = client.auth.onAuthStateChange.listen((data) {
      if (!skippedReplay) {
        skippedReplay = true;
        return;
      }
      // Only events that change *who* is signed in. `tokenRefreshed` fires on
      // its own roughly hourly and again whenever the app is resumed, and
      // rebuilding on it invalidated every provider watching auth — the
      // wallet, orders, portfolio and the rest all refetching under the
      // buyer's hands, mid-scroll, for a user who had not changed.
      // `initialSession` is the replay this listener already skips.
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userUpdated:
          ref.invalidateSelf();
        // A recovery link establishes a session and then has nothing to show
        // for it: the reset form is a route, and without this the user lands
        // back wherever they were with no password field in sight.
        case AuthChangeEvent.passwordRecovery:
          ref.invalidateSelf();
          appRouter.push(Routes.resetPassword);
        default:
          break;
      }
    });
    ref.onDispose(() {
      _disposed = true;
      sub.cancel();
    });

    // Answered synchronously, and that is the whole point.
    //
    // `Supabase.initialize()` restores the stored session, and `main` awaits
    // it before `runApp`, so whether someone is signed in is known without a
    // round trip. This used to `await` the `profiles` lookup as well, which
    // put the provider in `AsyncLoading` on every launch and every token
    // refresh — and `valueOrNull` reads null while loading, which is what the
    // ~15 screens gating on it took as "signed out". A signed-in user watched
    // "Masuk untuk melihat koleksimu" appear and then vanish.
    //
    // The username, avatar and admin flag are decoration on top of that
    // answer, so they arrive after, without holding it up.
    final user = client.auth.currentUser;
    if (user == null) return null;

    unawaited(_enrich(client, generation));
    return AppUser(id: user.id, email: user.email ?? '');
  }

  /// Replaces the bare session user with the profile-backed one.
  ///
  /// Failure is not fatal: the bare user already says the true thing about
  /// being signed in, and a missing username is better than a screen claiming
  /// nobody is logged in.
  Future<void> _enrich(SupabaseClient client, int generation) async {
    final full = await _load(client);
    if (_disposed || generation != _generation || full == null) return;
    state = AsyncData(full);
  }

  Future<AppUser?> _load(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    String? username;
    String? avatarUrl;
    var isAdmin = false;
    bool? onboarded;
    try {
      final profile = await client
          .from('profiles')
          .select('username, avatar_url, role, onboarded')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_authTimeout);
      username = profile?['username'] as String?;
      avatarUrl = proxyImageUrl(profile?['avatar_url'] as String?);
      isAdmin = profile?['role'] == 'admin';
      onboarded = profile?['onboarded'] as bool?;
    } catch (_) {
      // A failed profile lookup shouldn't block showing the signed-in state.
      // `onboarded` stays null, so a dropped request never traps someone
      // behind the onboarding modal.
    }
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      username: username,
      avatarUrl: avatarUrl,
      isAdmin: isAdmin,
      onboarded: onboarded,
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
      return userFacingError(e);
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
      return (signedIn: false, error: userFacingError(e));
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
      return (signedIn: false, error: userFacingError(e));
    } on SignInWithAppleException catch (e) {
      return (signedIn: false, error: e.toString());
    } on AuthException catch (e) {
      return (signedIn: false, error: userFacingError(e));
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

  /// Email and password only, as `app/signup/page.tsx` does. No username is
  /// asked for here: `handle_new_user` inserts the `profiles` row with a null
  /// one, and it is chosen later.
  ///
  /// This used to take a username and write it onto the profile — but only on
  /// the branch where a session already exists, and production requires email
  /// confirmation, so that branch never ran and the name the user typed was
  /// discarded every time.
  Future<SignUpResult> signUp(String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final response = await client.auth
          .signUp(email: email, password: password)
          .timeout(_authTimeout);
      if (response.session == null) {
        // Email confirmation required (production config) — no session yet.
        return const SignUpResult(SignUpOutcome.needsEmailConfirmation);
      }
      ref.invalidateSelf();
      return const SignUpResult(SignUpOutcome.signedIn);
    } on AuthException catch (e) {
      return SignUpResult(
        SignUpOutcome.error,
        errorMessage: userFacingError(e),
      );
    } on TimeoutException {
      return const SignUpResult(
        SignUpOutcome.error,
        errorMessage:
            'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.',
      );
    }
  }

  /// Claims [username] and closes onboarding, porting `handleSubmit` in
  /// `components/auth/onboarding-modal.tsx`. Returns null on success, else a
  /// message to show on the field.
  ///
  /// `display_name` is mirrored onto the auth user as web does, so the name
  /// Supabase reports matches the one the profile carries.
  Future<String?> completeOnboarding(String username) async {
    final client = ref.read(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) return 'Sesi berakhir. Masuk lagi untuk melanjutkan.';

    try {
      await client
          .from('profiles')
          .update({'username': username, 'onboarded': true})
          .eq('id', user.id)
          .timeout(_authTimeout);
    } on PostgrestException catch (e) {
      // The debounced check can go stale between the last keystroke and the
      // submit; the unique index is what actually decides.
      if (e.code == '23505') return 'Username sudah dipakai';
      return 'Terjadi kesalahan, coba lagi';
    } on TimeoutException {
      return 'Waktu koneksi habis. Coba lagi.';
    }

    try {
      await client.auth
          .updateUser(UserAttributes(data: {'display_name': username}))
          .timeout(_authTimeout);
    } catch (_) {
      // The profile row is what the app reads; a failed metadata mirror is
      // not worth sending the user back through onboarding.
    }

    ref.invalidateSelf();
    return null;
  }

  Future<void> signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut().timeout(_authTimeout);
    // The primary collection id is memoised per user for the life of the
    // process; without this the next account signed in on the same device
    // would write into the previous one's collection.
    clearPrimaryCollectionCache();
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
      return userFacingError(e);
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
      return userFacingError(e);
    } on TimeoutException {
      return 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.';
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
