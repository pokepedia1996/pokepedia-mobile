import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/referral/presentation/referral_pack_page.dart';

void main() {
  test('tearProgress: 72% of the pack width tears, either direction', () {
    expect(tearProgress(0, 200), 0);
    expect(tearProgress(72, 200), closeTo(0.5, 1e-9));
    expect(tearProgress(144, 200), 1);
    expect(tearProgress(-144, 200), 1);
    expect(tearProgress(-72, 200), closeTo(0.5, 1e-9));
    expect(tearProgress(400, 200), 1);
  });

  test('tearEdge: 17 points from 6% to 94%, zigzag around the 7.5% line', () {
    final edge = tearEdge(const Size(200, 400));
    expect(edge, hasLength(17));
    expect(edge.first.dx, closeTo(12, 1e-9));
    expect(edge.last.dx, closeTo(188, 1e-9));
    expect(edge[0].dy, lessThan(30));
    expect(edge[1].dy, greaterThan(30));
    expect(edge[2].dy, lessThan(30));
  });
}
