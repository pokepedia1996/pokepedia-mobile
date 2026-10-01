import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pokepedia_mobile/app/app.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';

void main() {
  // `appRouter` listens to `Supabase.instance` and reads the session in its
  // redirect, so the app cannot be built until a client exists. Pointed at a
  // local address that is never actually contacted.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  // Asserts the shell, not the feed. Everything Home renders below the nav
  // now loads from Supabase behind `HomeLoadingGate`, so with no reachable
  // backend there is no content to find — what still holds, and what this
  // test is named for, is that the app boots and lands on the Home tab.
  testWidgets('App boots to the Home tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PokepediaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Beranda'), findsOneWidget);

    final nav = tester.widget<AppBottomNav>(find.byType(AppBottomNav));
    expect(nav.currentIndex, 0);
  });
}
