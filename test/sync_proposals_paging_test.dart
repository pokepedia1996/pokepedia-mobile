import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/paging.dart';

/// Serves [total] rows keyed `r<n>`, recording each requested range.
({Future<List<String>> Function(int, int) fetch, List<(int, int)> ranges})
_serve(int total) {
  final ranges = <(int, int)>[];
  Future<List<String>> fetch(int from, int to) async {
    ranges.add((from, to));
    final end = to + 1 < total ? to + 1 : total;
    return [for (var i = from; i < end; i++) 'r$i'];
  }

  return (fetch: fetch, ranges: ranges);
}

void main() {
  test('walks past the first page', () async {
    final s = _serve(65);
    final rows = await fetchAllPages(s.fetch, keyOf: (r) => r, pageSize: 50);
    expect(rows, hasLength(65));
    expect(s.ranges, [(0, 49), (50, 99)]);
  });

  test('stops after one request when everything fits', () async {
    final s = _serve(12);
    expect(await fetchAllPages(s.fetch, keyOf: (r) => r), hasLength(12));
    expect(s.ranges, hasLength(1));
  });

  test('an exact multiple costs one empty page, not a missed one', () async {
    final s = _serve(100);
    expect(
      await fetchAllPages(s.fetch, keyOf: (r) => r, pageSize: 50),
      hasLength(100),
    );
    expect(s.ranges, hasLength(3));
  });

  test('de-duplicates a row that shifts across a page boundary', () async {
    Future<List<String>> fetch(int from, int to) async =>
        from == 0 ? [for (var i = 0; i < 50; i++) 'r$i'] : ['r49', 'r50'];
    final rows = await fetchAllPages(fetch, keyOf: (r) => r, pageSize: 50);
    expect(rows, hasLength(51));
    expect(rows.toSet(), hasLength(51));
  });

  test('stops at the page bound even if every page is full', () async {
    final s = _serve(1 << 20);
    final rows = await fetchAllPages(
      s.fetch,
      keyOf: (r) => r,
      pageSize: 10,
      maxPages: 3,
    );
    expect(rows, hasLength(30));
    expect(s.ranges, hasLength(3));
  });
}
