import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

/// Bounds every auth network call so a stalled connection surfaces as an
/// error instead of leaving the caller's loading state stuck forever.
const _authTimeout = Duration(seconds: 15);

/// The signed-in user, combining `auth.users` (session) with `profiles`
/// (username).
class AppUser {
  const AppUser({required this.id, required this.email, this.username});

  final String id;
  final String email;
  final String? username;
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
        debugPrint('PUNTEN ${user?.email}');
    if (user == null) return null;
    String? username;
    try {
      final profile = await client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_authTimeout);
      username = profile?['username'] as String?;
    } catch (_) {
      // A failed profile lookup shouldn't block showing the signed-in state.
    }
    return AppUser(id: user.id, email: user.email ?? '', username: username);
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

  Future<SignUpResult> signUp(String username, String email, String password) async {
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
        errorMessage: 'Waktu koneksi habis. Periksa koneksi internet atau coba lagi.',
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

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);
