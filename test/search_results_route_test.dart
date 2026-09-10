import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';

/// "Cari semua" hands the typed query to a results page over the URL, so the
/// encoding is the contract between them: a card name with a space or a "&"
/// that is not escaped arrives truncated, and the page searches for half of
/// what was asked.
void main() {
  test('carries the query as an encoded parameter', () {
    expect(Routes.searchResults('mewtwo'), '/search?q=mewtwo');
  });

  test('escapes what a query string would otherwise eat', () {
    expect(
      Routes.searchResults('mewtwo ex'),
      anyOf('/search?q=mewtwo+ex', '/search?q=mewtwo%20ex'),
    );
    expect(Routes.searchResults('a&b'), '/search?q=a%26b');
    expect(Routes.searchResults('100%'), '/search?q=100%25');
  });

  test('is a different destination from the filter form', () {
    // The form is where you build a query; this is where you read results.
    expect(Routes.searchResults('pikachu'), isNot(startsWith(Routes.search)));
  });
}
