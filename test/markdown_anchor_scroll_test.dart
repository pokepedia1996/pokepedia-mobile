import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/simple_markdown.dart';

/// Tapping an entry in a legal document's table of contents jumps to the
/// section it names. The link and the heading are worded differently on
/// purpose here, so the finders can tell them apart.
final _doc =
    '''
# Judul Dokumen

- [Ke Bagian Akhir](#bagian-akhir)
- [Tautan Rusak](#tidak-ada-bagian-ini)

'''
    '${'Paragraf pengisi supaya bagian akhir jatuh di luar layar.\n\n' * 40}'
    '''
## Bagian Akhir

'''
    // Filler after the heading too, or the list hits maxScrollExtent before
    // the heading reaches the top and the alignment cannot be judged.
    '${'Isi bagian akhir.\n\n' * 40}';

Future<ScrollableState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [SimpleMarkdown(data: _doc)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<ScrollableState>(find.byType(Scrollable));
}

void main() {
  testWidgets('a table-of-contents entry scrolls to its heading', (
    tester,
  ) async {
    final scrollable = await _pump(tester);
    expect(scrollable.position.pixels, 0);

    await tester.tapOnText(find.textRange.ofSubstring('Ke Bagian Akhir'));
    await tester.pumpAndSettle();

    expect(
      scrollable.position.pixels,
      greaterThan(0),
      reason: 'the tap should have moved the document',
    );

    // And moved it to the right place: the heading sits at the top of the
    // viewport rather than merely somewhere on screen.
    final headingTop = tester.getTopLeft(find.text('Bagian Akhir')).dy;
    expect(headingTop, lessThan(80));
    expect(headingTop, greaterThanOrEqualTo(-1));
  });

  testWidgets('a link naming no heading does nothing', (tester) async {
    final scrollable = await _pump(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Tautan Rusak'));
    await tester.pumpAndSettle();

    // Staying put beats jumping somewhere arbitrary when a heading has been
    // renamed out from under the document's own contents.
    expect(scrollable.position.pixels, 0);
  });
}
