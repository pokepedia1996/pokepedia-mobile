import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the contract between `env.json` and the code that reads it.
///
/// `env.json` is gitignored, so nothing else in the repo records which keys
/// the app needs — `env.example.json` is that record, and it is only useful
/// if it stays in step with `String.fromEnvironment` in the source.
void main() {
  final example =
      jsonDecode(File('env.example.json').readAsStringSync())
          as Map<String, dynamic>;
  final config = File('lib/core/config/app_config.dart').readAsStringSync();

  /// Every key the source actually reads.
  final read = RegExp(
    r"String\.fromEnvironment\(\s*'([A-Z_]+)'",
  ).allMatches(config).map((m) => m.group(1)!).toSet();

  test('the example lists every key the app reads', () {
    // A key added to the code but not the example is invisible to anyone
    // setting the project up — they get a runtime failure with no clue.
    final documented = example.keys.where((k) => !k.startsWith('_')).toSet();
    expect(read.difference(documented), isEmpty);
  });

  test('the example lists no key the app ignores', () {
    // The reverse rot: a key that was renamed or dropped leaves a line
    // everyone keeps faithfully filling in for no effect.
    final documented = example.keys.where((k) => !k.startsWith('_')).toSet();
    expect(documented.difference(read), isEmpty);
  });

  test('both URL halves are configurable together', () {
    // The app's token is validated by the API's Supabase, so pointing these
    // at different stacks 401s every authenticated route. Neither may be
    // hardcoded while the other is configurable.
    expect(read, containsAll(['SUPABASE_URL', 'APP_URL']));
  });

  test('the example ships no real credential', () {
    // It is committed; env.json is not. A key pasted here leaks.
    for (final entry in example.entries) {
      if (entry.key.startsWith('_')) continue;
      final value = entry.value as String;
      expect(
        value,
        isNot(startsWith('sb_publishable_')),
        reason: '${entry.key} looks like a real Supabase key',
      );
      expect(
        value,
        isNot(contains('.apps.googleusercontent.com')),
        reason: '${entry.key} looks like a real Google client id',
      );
    }
  });

  test('example URLs point at a local stack, never production', () {
    // A default that silently reaches production is the dangerous one —
    // it works, so nobody notices until test data lands in the real DB.
    for (final key in ['SUPABASE_URL', 'APP_URL']) {
      final value = example[key] as String;
      if (value.isEmpty) continue;
      expect(value, isNot(contains('pokepedia.id')), reason: key);
    }
  });

  test('no URL is hardcoded to a developer LAN address', () {
    // These get committed by accident and then break for everyone else —
    // including, once, in the release branch of this very file.
    expect(
      RegExp(r'192\.168\.\d+\.\d+').hasMatch(config),
      isFalse,
      reason: 'app_config.dart should carry no LAN address',
    );
  });
}
