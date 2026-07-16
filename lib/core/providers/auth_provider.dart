import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dummy stand-in for `components/auth/auth-provider.tsx`. Holds a local
/// guest/logged-in flag so the Account screen has something to react to —
/// no real authentication backend is wired up in this UI-only pass.
class DummyUser {
  const DummyUser({required this.username, required this.email});

  final String username;
  final String email;
}

class AuthNotifier extends Notifier<DummyUser?> {
  @override
  DummyUser? build() =>
      const DummyUser(username: 'ashketchum', email: 'user1@test.com');

  void logIn() => state =
      const DummyUser(username: 'ashketchum', email: 'user1@test.com');

  void logOut() => state = null;
}

final authProvider = NotifierProvider<AuthNotifier, DummyUser?>(
  AuthNotifier.new,
);
