import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A path registered twice is a silent trap: go_router matches the first
/// registration and the second becomes dead code, so a builder edited there
/// changes nothing — and if the winner is a shell branch, pushing that path
/// from outside the shell throws instead of opening a page.
///
/// `/advanced-search` was registered both as the Pencarian branch and as a
/// top-level route; the results page's filter button pushed it and crashed.
///
/// Asserted against the source because the router itself cannot be built in a
/// test — it listens to `Supabase.instance`, which needs a live client.
void main() {
  final source = File('lib/app/router/app_router.dart').readAsStringSync();

  /// Every top-level `path:` in the route table, in order.
  ///
  /// Relative segments — ':slug', 'offers/:slug' — are scoped to their parent
  /// route and repeat legitimately, so only absolute paths count: string
  /// literals starting with a slash, and the `Routes` constants, which are
  /// all absolute.
  final paths = RegExp(
    "path:\\s*(?:Routes\\.(\\w+)|'(/[^']*)')",
  ).allMatches(source).map((m) => m.group(1) ?? m.group(2)!).toList();

  test('registers each route path once', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final path in paths) {
      if (!seen.add(path)) duplicates.add(path);
    }
    expect(
      duplicates,
      isEmpty,
      reason:
          'these paths are registered more than once, so every registration '
          'after the first is unreachable: $duplicates',
    );
  });

  test('the search form stays a single registration', () {
    // Named directly because this is the one that broke, and because the
    // fix — deleting the top-level copy — is easy to undo by accident.
    expect(paths.where((p) => p == 'search'), hasLength(1));
  });
}
