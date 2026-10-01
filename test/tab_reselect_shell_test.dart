import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/app.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/app/tab_reselect.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Only the tab already open raises the signal. Firing it on every tap would
/// re-fetch a feed the reader is arriving at rather than returning to, which
/// is the one moment it is already loading anyway.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('tapping the open tab raises it, moving to another does not', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PokepediaApp(),
      ),
    );
    await tester.pumpAndSettle();

    final market = AppBottomNav.tabPaths.indexOf(Routes.market);
    // Scoped to the pill: the Market page's own title says "Market" too.
    final tab = find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.text('Market'),
    );

    // Arriving at Market is navigation, not a re-tap.
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(container.read(tabReselectProvider).index, -1);

    // Tapping it again, now that it is the open tab, is the gesture.
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(container.read(tabReselectProvider).index, market);
  });
}
