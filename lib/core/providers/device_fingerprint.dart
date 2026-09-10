import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A stable per-install identifier, used for the same-device self-trade
/// guard.
///
/// `device_users` joins (device, user) pairs so the server can tell that two
/// accounts are the same person on one device — the `same_device_self_trade`
/// rule that stops someone buying their own listing from a second account.
/// Every browser client is subject to it. A native client that records
/// nothing is simply exempt, which is a hole rather than a feature, so the
/// app registers itself the same way.
///
/// Generated once and kept in local storage: not a hardware id, nothing
/// about the device, and it resets on reinstall. That's the same guarantee
/// the web's cookie-scoped fingerprint gives.
class DeviceFingerprint {
  DeviceFingerprint(this._client);

  final SupabaseClient _client;

  static const _key = 'device_fingerprint';

  /// The server validates against `/^[a-f0-9]{16,128}$/i` and silently drops
  /// anything else, so this emits exactly that: 32 lowercase hex chars.
  static String _generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  String? _cached;

  Future<String> value() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_key);
    if (value == null || !RegExp(r'^[a-f0-9]{16,128}$').hasMatch(value)) {
      value = _generate();
      await prefs.setString(_key, value);
    }
    _cached = value;
    return value;
  }

  /// Ports `recordDeviceUser`. Writes straight to `device_users`, whose
  /// policies are `auth.uid() = user_id` for select/insert/update — so this
  /// needs no server route, and can't touch anyone else's pairing.
  ///
  /// `ip_address` is left null on purpose: the app can't see its own public
  /// IP, and inventing one would be worse than the column being empty. The
  /// device/user join is what the guard actually keys on.
  Future<void> record() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('device_users').upsert({
        'device_fingerprint': await value(),
        'user_id': userId,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'device_fingerprint,user_id');
    } on PostgrestException {
      // Best effort. A missed pairing weakens a fraud signal; it must never
      // be the reason someone can't add to their cart.
    }
  }
}

final deviceFingerprintProvider = Provider(
  (ref) => DeviceFingerprint(Supabase.instance.client),
);
