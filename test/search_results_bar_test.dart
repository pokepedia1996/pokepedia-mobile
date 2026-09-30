import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/search/presentation/search_results_page.dart';
import 'package:pokepedia_mobile/shared/widgets/quick_search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedOut extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Widget _page(String query) => ProviderScope(
  overrides: [authProvider.overrideWith(_SignedOut.new)],
  child: MaterialApp(
    theme: AppTheme.light,
    home: SearchResultsPage(query: query),
  ),
);

/// Results used to be a dead end: the query was printed as a heading and the
/// only way to change it was the back button, which threw the results away
/// along with the page's scroll position.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the results page carries a search bar', (tester) async {
    // A query below the minimum: the page shows its placeholder and does no
    // network work, which is also the moment the bar matters most.
    await tester.pumpWidget(_page('a'));
    await tester.pump();

    expect(find.byType(QuickSearchField), findsOneWidget);
  });

  testWidgets('the bar starts on the query being shown', (tester) async {
    await tester.pumpWidget(_page('a'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'a');
  });
}
