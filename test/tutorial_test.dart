import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/content/presentation/terms_page.dart';
import 'package:pokepedia_mobile/features/content/presentation/tutorial_page.dart';
import 'package:pokepedia_mobile/features/content/repository/tutorial_docs.dart';

/// The guides are bundled markdown split by hand, so the parsing is where
/// this can quietly go wrong: a missed FAQ heading swallows the answers into
/// the body, and a kept H1 shows the title twice.
void main() {
  group('splitTutorial', () {
    test('drops the H1 and lifts the FAQ out of the body', () {
      final result = splitTutorial('''
# Membuat Akun

Buat akun dalam beberapa langkah.

## FAQ

### Link verifikasi tidak masuk?

Cek folder Spam.

### Bisa ganti username?

Bisa, dengan batasan.
''');

      expect(result.body, 'Buat akun dalam beberapa langkah.');
      expect(result.faq, hasLength(2));
      expect(result.faq.first.question, 'Link verifikasi tidak masuk?');
      expect(result.faq.first.answer, 'Cek folder Spam.');
      expect(result.faq.last.answer, 'Bisa, dengan batasan.');
    });

    test('a guide without a FAQ keeps its whole body', () {
      final result = splitTutorial(
        '# Judul\n\nIsi panduan.\n\n## Langkah\n\n1. Satu.',
      );

      expect(result.faq, isEmpty);
      expect(result.body, contains('## Langkah'));
      expect(result.body, isNot(contains('# Judul')));
    });
  });

  testWidgets('every bundled guide is readable', (tester) async {
    // The index and the assets are edited separately; a typo in one leaves a
    // tile that opens onto nothing.
    for (final doc in tutorialDocs) {
      final raw = await rootBundle.loadString(doc.asset);
      expect(raw, isNotEmpty, reason: '${doc.slug} is empty');
      expect(splitTutorial(raw).body, isNotEmpty, reason: '${doc.slug} body');
    }
  });

  testWidgets('every legal document is bundled and non-empty', (tester) async {
    // Same failure mode as the guides: the page reads by slug, so a missing
    // or misnamed file is a screen that loads onto an error.
    for (final slug in TermsPage.titles.keys) {
      final raw = await rootBundle.loadString('assets/legal/$slug.md');
      expect(raw, isNotEmpty, reason: slug);
      expect(raw, contains('# '), reason: '$slug has no heading');
    }
  });

  testWidgets('lists every guide, collapsed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const TutorialPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tutorial'), findsOneWidget);
    for (final doc in tutorialDocs) {
      // Off-screen tiles aren't built, so only assert the ones that are.
      if (find.text(doc.title).evaluate().isEmpty) continue;
      expect(find.text(doc.description), findsOneWidget);
    }
    // Collapsed: no body is in the tree yet.
    expect(find.textContaining('Cek folder'), findsNothing);
  });
}
