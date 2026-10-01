import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/simple_markdown.dart';

/// The legal documents open with their own table of contents — a bulleted
/// list of `[Label](#slug)` links. Those only scroll anywhere if the slug the
/// renderer derives from a heading matches the slug the document was written
/// with, and both sides are edited by hand. This walks the real bundled files
/// so a renamed heading or a mistyped anchor fails here rather than silently
/// becoming a link that does nothing.
void main() {
  final docs = Directory(
    'assets/legal',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList();

  test('there are documents to check', () {
    expect(docs, isNotEmpty);
  });

  for (final doc in docs) {
    final name = doc.uri.pathSegments.last;
    final lines = doc.readAsLinesSync();

    final headingSlugs = {
      for (final line in lines)
        if (RegExp(r'^#{1,4} ').hasMatch(line.trim()))
          SimpleMarkdown.headingSlug(
            line.trim().replaceFirst(RegExp(r'^#{1,4} '), ''),
          ),
    };

    final linked = [
      for (final match in RegExp(
        r'\]\(#([^)]+)\)',
      ).allMatches(lines.join('\n')))
        match.group(1)!,
    ];

    test('$name: every in-document link points at a real heading', () {
      for (final slug in linked) {
        expect(
          headingSlugs,
          contains(slug),
          reason:
              '$name links to #$slug, but no heading slugifies to that. '
              'Headings present: ${headingSlugs.join(", ")}',
        );
      }
    });
  }

  group('headingSlug follows GitHub', () {
    test('drops punctuation and lowercases', () {
      expect(SimpleMarkdown.headingSlug('A. Definisi'), 'a-definisi');
      expect(
        SimpleMarkdown.headingSlug('B. Akun, Password dan Keamanan'),
        'b-akun-password-dan-keamanan',
      );
    });

    test('keeps the double hyphen an ampersand leaves behind', () {
      // GitHub turns " & " into two hyphens, and the document's own anchor
      // was written that way — collapsing would break it.
      expect(
        SimpleMarkdown.headingSlug('1. Konsep Dasar: Integrity & Imperfection'),
        '1-konsep-dasar-integrity--imperfection',
      );
    });
  });
}
