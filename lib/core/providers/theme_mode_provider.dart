import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark/system toggle, ported from
/// `components/layout/theme-provider.tsx`.
///
/// The choice is kept on the device, so closing the app no longer drops it
/// back to the system theme. It is read once in `main` before `runApp`
/// ([load]), like `IntroFlag`, so the first frame is already in the chosen
/// theme instead of flashing the system one.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'pokepedia.theme-mode.v1';

  /// What [load] found. System until then: tests and previews that never
  /// call it follow the device, as the app did before the choice was kept.
  static ThemeMode _saved = ThemeMode.system;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _saved = _parse(prefs.getString(_key));
    } catch (_) {
      // Storage unreadable: follow the device rather than fail the launch.
      _saved = ThemeMode.system;
    }
  }

  static ThemeMode _parse(String? name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return ThemeMode.system;
  }

  @override
  ThemeMode build() => _saved;

  void cycle() {
    set(switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    });
  }

  void set(ThemeMode mode) {
    state = mode;
    unawaited(_persist(mode));
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Not saved, but the switch itself already happened.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
