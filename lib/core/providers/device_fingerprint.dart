import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stable per-install identifier, used for the same-device self-trade
/// guard.
///
/// `device_users` joins (device, user) pairs so the server can tell that two
/// accounts are the same person on one device — the `same_device_self_trade`
/// rule that stops someone buying their own listing from a second account.
/// The app sends this value as `deviceFingerprint` on `/api/cart` and
/// `/api/listings`, and those routes record the pairing server-side, the way
/// `recordDeviceUser` does for the browser.
///
/// Generated once and kept in local storage: not a hardware id, nothing
/// about the device, and it resets on reinstall. That's the same guarantee
/// the web's cookie-scoped fingerprint gives.
class DeviceFingerprint {
  DeviceFingerprint();

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
}

final deviceFingerprintProvider = Provider((ref) => DeviceFingerprint());
