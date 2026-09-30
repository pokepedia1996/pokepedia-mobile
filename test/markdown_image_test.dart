import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/simple_markdown.dart';

Future<void> _pump(WidgetTester tester, String data) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(children: [SimpleMarkdown(data: data)]),
      ),
    ),
  );
  await tester.pump();
}

/// The tutorials are screenshots with a sentence each. They used to render as
/// the literal text "!" followed by a link titled with the alt text, because
/// the inline link pattern matched everything after the "!" — so the guide
/// that is mostly pictures showed none of them.
void main() {
  testWidgets('a screenshot renders as a picture', (tester) async {
    await _pump(
      tester,
      '1. Buka halaman detail kartu.\n\n'
      '   ![Halaman Detail Kartu](https://cdn2.pokepedia.id/t/4.1.webp)\n',
    );

    expect(find.byType(Image), findsOneWidget);
    // Not as the broken text it used to be.
    expect(find.textContaining('!Halaman Detail Kartu'), findsNothing);
    expect(find.textContaining('](https://'), findsNothing);
  });

  testWidgets('the alt text stands in when the picture cannot load', (
    tester,
  ) async {
    await _pump(tester, '![Keranjang](https://cdn2.pokepedia.id/t/4.3.webp)');

    // `Image.network` fails immediately in tests — there is no HTTP client —
    // so the error branch is what a pump lands on, which is exactly the
    // branch worth pinning: a missing screenshot must not leave a blank gap
    // where a step was.
    await tester.pump();
    expect(find.text('Keranjang'), findsOneWidget);
  });

  testWidgets('a link is still a link', (tester) async {
    await _pump(tester, 'Lihat [Keranjang](https://pokepedia.id/cart) dulu.');

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Keranjang', findRichText: true), findsWidgets);
  });
}
