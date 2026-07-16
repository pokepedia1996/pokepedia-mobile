import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokepedia_mobile/app/app.dart';

void main() {
  testWidgets('App boots to the Home tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PokepediaApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jelajahi Market'), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
  });
}
