import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/utils/price_input_formatter.dart';

/// A price field's digits are read in thousands: "301198" has to be counted
/// before it can be read, and 30.120 against 301.200 is one glance with the
/// separators and a squint without them.
void main() {
  const formatter = PriceInputFormatter();

  TextEditingValue typed(String text, {int? caret}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  TextEditingValue format(String before, String after, {int? caret}) =>
      formatter.formatEditUpdate(typed(before), typed(after, caret: caret));

  test('groups as it is typed', () {
    expect(format('30119', '301198').text, '301.198');
    expect(format('1', '12').text, '12');
    expect(format('999', '9999').text, '9.999');
    expect(format('999999', '9999999').text, '9.999.999');
  });

  test('an emptied field stays empty', () {
    // Not "0" — nothing typed is not an offer of nothing.
    expect(format('1', '').text, '');
  });

  test('the caret stays put as separators appear', () {
    // Typing the last digit of "301198": the caret belongs at the end, not
    // walked left by the dot that just appeared.
    final result = format('30119', '301198');
    expect(result.selection.baseOffset, result.text.length);
  });

  test('the caret keeps its place when editing mid-number', () {
    // "1.198" with the caret after the "1" of 198; a digit typed there lands
    // in the same spot rather than jumping.
    final result = format('1198', '11198', caret: 2);
    expect(result.text, '11.198');
    // Two digits still follow the caret on each side of the change.
    final after = result.text.substring(result.selection.baseOffset);
    expect(after.replaceAll(RegExp(r'\D'), '').length, 3);
  });

  test('what the form parses is unchanged', () {
    final text = format('30119', '301198').text;
    expect(int.parse(text.replaceAll(RegExp(r'\D'), '')), 301198);
  });
}
