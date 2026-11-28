import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The theme a user picks has to survive closing the app: it used to start
/// every launch on the system theme.
void main() {
  const key = 'pokepedia.theme-mode.v1';

  Future<ProviderContainer> launch(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    await ThemeModeNotifier.load();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('a new launch opens in the saved theme', () async {
    final app = await launch({key: 'dark'});
    expect(app.read(themeModeProvider), ThemeMode.dark);
  });

  test('nothing saved, or something unreadable, follows the device', () async {
    expect((await launch({})).read(themeModeProvider), ThemeMode.system);
    expect(
      (await launch({key: 'purple'})).read(themeModeProvider),
      ThemeMode.system,
    );
  });

  test('a change is saved for the next launch', () async {
    final app = await launch({});
    app.read(themeModeProvider.notifier).cycle();
    expect(app.read(themeModeProvider), ThemeMode.light);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), 'light');

    await ThemeModeNotifier.load();
    final relaunched = ProviderContainer();
    addTearDown(relaunched.dispose);
    expect(relaunched.read(themeModeProvider), ThemeMode.light);
  });
}
