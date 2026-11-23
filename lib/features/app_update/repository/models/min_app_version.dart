import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The `min_app_version` row of `app_config`: the oldest version allowed to
/// run on each platform, and where its store page is.
///
/// ```json
/// {"ios": "1.3.0", "android": "1.3.0",
///  "iosStoreUrl": "https://apps.apple.com/app/id…"}
/// ```
///
/// A platform left out has no minimum. Both store URLs are optional: each
/// defaults to the app's own page in its store.
class MinAppVersion {
  const MinAppVersion({
    this.ios,
    this.android,
    this.iosStoreUrl,
    this.androidStoreUrl,
  });

  final String? ios;
  final String? android;
  final String? iosStoreUrl;
  final String? androidStoreUrl;

  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=id.pokepedia.app';

  /// The app's App Store page, for an iOS minimum set without one.
  static const _appStoreUrl =
      'https://apps.apple.com/us/app/pokepedia-id/id6808564481';

  /// Null for anything that isn't the object above: a bad row must not lock
  /// everyone out of the app.
  static MinAppVersion? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      String? text(String key) {
        final value = json[key];
        return value is String && value.trim().isNotEmpty ? value.trim() : null;
      }

      return MinAppVersion(
        ios: text('ios'),
        android: text('android'),
        iosStoreUrl: text('iosStoreUrl'),
        androidStoreUrl: text('androidStoreUrl'),
      );
    } on FormatException {
      return null;
    }
  }

  /// The update [installed] needs on [platform], or null when it may run.
  RequiredUpdate? requiredFor({
    required TargetPlatform platform,
    required String installed,
  }) {
    final (minimum, storeUrl) = switch (platform) {
      TargetPlatform.iOS => (ios, iosStoreUrl ?? _appStoreUrl),
      TargetPlatform.android => (android, androidStoreUrl ?? _playStoreUrl),
      _ => (null, ''),
    };
    if (minimum == null || !isVersionOlder(installed, minimum)) return null;
    return RequiredUpdate(minimum: minimum, storeUrl: storeUrl);
  }
}

/// An installed version too old to run, and where to get a newer one.
@immutable
class RequiredUpdate {
  const RequiredUpdate({required this.minimum, required this.storeUrl});

  final String minimum;
  final String storeUrl;

  @override
  bool operator ==(Object other) =>
      other is RequiredUpdate &&
      other.minimum == minimum &&
      other.storeUrl == storeUrl;

  @override
  int get hashCode => Object.hash(minimum, storeUrl);
}

/// Whether [installed] comes before [minimum], comparing `major.minor.patch`
/// and ignoring any `+build`. False when either can't be read, for the same
/// reason [MinAppVersion.parse] is lenient.
bool isVersionOlder(String installed, String minimum) {
  final a = _parts(installed);
  final b = _parts(minimum);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

List<int>? _parts(String version) {
  final core = version.trim().split('+').first;
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}
