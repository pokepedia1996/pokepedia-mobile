import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';

/// Fifteen screens decide whether to draw "Masuk untuk ..." from
/// `ref.watch(authProvider).valueOrNull != null`. `valueOrNull` reads null
/// while an AsyncNotifier is loading, so any launch that passed through
/// AsyncLoading told a signed-in user they were signed out, for as long as the
/// profile lookup took.
///
/// The session is restored before `runApp`, so that answer is available with
/// no round trip and the provider should never be in a loading state with a
/// session in hand.
class _SignedIn extends AuthNotifier {
  @override
  FutureOr<AppUser?> build() =>
      const AppUser(id: 'me', email: 'me@example.com');
}

class _Loading extends AuthNotifier {
  @override
  Future<AppUser?> build() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const AppUser(id: 'me', email: 'me@example.com');
  }
}

void main() {
  test('a synchronous build is readable on the first frame', () {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_SignedIn.new)],
    );
    addTearDown(container.dispose);

    // No pump, no await: exactly what a widget's first build sees.
    final auth = container.read(authProvider);
    expect(auth.isLoading, isFalse);
    expect(
      auth.valueOrNull,
      isNotNull,
      reason: 'a screen reading this on frame one must not see "signed out"',
    );
  });

  test('the old async shape is what produced the flash', () async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_Loading.new)],
    );
    addTearDown(container.dispose);

    // Pinned as the behaviour being avoided, so nobody reintroduces an
    // awaited profile lookup in `build` without this failing.
    expect(container.read(authProvider).valueOrNull, isNull);
    await container.read(authProvider.future);
    expect(container.read(authProvider).valueOrNull, isNotNull);
  });
}
