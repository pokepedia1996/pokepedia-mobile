import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/app_pagination.dart';

void main() {
  group('pageNumbers', () {
    test('lists every page when there are few', () {
      expect(pageNumbers(1, 1), [1]);
      expect(pageNumbers(3, 5), [1, 2, 3, 4, 5]);
    });

    test('collapses both sides around a middle page', () {
      expect(pageNumbers(6, 12), [1, null, 5, 6, 7, null, 12]);
    });

    test('fills a one-page gap instead of an ellipsis', () {
      expect(pageNumbers(3, 12), [1, 2, 3, 4, null, 12]);
      expect(pageNumbers(10, 12), [1, null, 9, 10, 11, 12]);
    });

    test('keeps the ends at the first and last page', () {
      expect(pageNumbers(1, 12), [1, 2, null, 12]);
      expect(pageNumbers(12, 12), [1, null, 11, 12]);
    });
  });
}
