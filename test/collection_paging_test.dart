import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/utils/paged_rows.dart';

/// A collection read with no `range` stops at Supabase's "Max rows" — 1000 by
/// default — and does so silently. An 8,495-card collection reported "1000
/// kartu unik" on Beranda, and every total downstream agreed with it, because
/// nothing in the chain knew the read had been cut short.
void main() {
  test('the ceiling is high enough for a real collection', () {
    expect(maxCollectionRows, 15000);
    // Above the server's default page, or paging would never happen.
    expect(maxCollectionRows, greaterThan(1000));
  });

  group('paging arithmetic', () {
    // Mirrors the loop in `_pagedRows`: pages of 1000 until the ceiling.
    List<({int from, int to})> pages(int max, {int size = 1000}) => [
      for (var from = 0; from < max; from += size)
        (from: from, to: (from + size > max ? max : from + size) - 1),
    ];

    test('covers the whole ceiling without gaps or overlap', () {
      final windows = pages(maxCollectionRows);

      expect(windows.first.from, 0);
      expect(windows.last.to, maxCollectionRows - 1);
      for (var i = 1; i < windows.length; i++) {
        expect(
          windows[i].from,
          windows[i - 1].to + 1,
          reason: 'page $i must start where page ${i - 1} ended',
        );
      }
    });

    test('a ceiling that is not a whole number of pages still ends on it', () {
      final windows = pages(2500);
      expect(windows.last.to, 2499);
      expect(windows.length, 3);
    });
  });

  // The windows above are arithmetic; this runs the loop itself against a
  // server that caps every response at 1000 rows, the way Supabase does.
  test('pagedRows reads past a 1000-row server cap', () async {
    final table = [
      for (var i = 0; i < 2537; i++) <String, dynamic>{'id': i},
    ];
    final rows = await pagedRows((from, to) async {
      if (from >= table.length) return <Map<String, dynamic>>[];
      final end = [to + 1, from + 1000, table.length].reduce(min);
      return table.sublist(from, end);
    });
    expect(rows.length, 2537);
    expect(rows.last['id'], 2536);
  });
}
