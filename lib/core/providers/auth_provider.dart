import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

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
    final sub = client.auth.onAuthStateChange.listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);
    return _load(client);
  }

  Future<AppUser?> _load(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    String? username;
    try {
      final profile = await client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      username = profile?['username'] as String?;
    } catch (_) {
      // A failed profile lookup shouldn't block showing the signed-in state.
    }
    return AppUser(id: user.id, email: user.email ?? '', username: username);
  }

  Future<String?> signIn(String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      ref.invalidateSelf();
      await future;
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<SignUpResult> signUp(String username, String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final response = await client.auth.signUp(email: email, password: password);
      if (response.session == null) {
        // Email confirmation required (production config) — no session yet.
        return const SignUpResult(SignUpOutcome.needsEmailConfirmation);
      }
      // `handle_new_user` already inserted a bare `profiles` row (trigger,
      // server-side); persist the chosen username onto it now that we
      // have a session to satisfy RLS.
      try {
        await client.from('profiles').update({'username': username}).eq('id', response.user!.id);
      } catch (_) {
        // Username format/uniqueness conflicts shouldn't block sign-up —
        // it can be set later from account settings.
      }
      ref.invalidateSelf();
      await future;
      return const SignUpResult(SignUpOutcome.signedIn);
    } on AuthException catch (e) {
      return SignUpResult(SignUpOutcome.error, errorMessage: e.message);
    }
  }

  Future<void> signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut();
  }

  /// Fire-and-forget like web's `resetPasswordForEmail` call — always
  /// succeeds from the caller's perspective so it doesn't leak whether an
  /// email exists in the system.
  Future<String?> requestPasswordReset(String email) async {
    try {
      await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<String?> updatePassword(String password) async {
    try {
      await ref.read(supabaseClientProvider).auth.updateUser(UserAttributes(password: password));
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);
