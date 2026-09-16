import 'package:flutter/services.dart';

import '../../core/utils/formatters.dart';

/// Groups a money field's digits as they are typed — "301198" shows as
/// "301.198".
///
/// A price is read in thousands, and an ungrouped run of digits has to be
/// counted before it can be read at all: the difference between 30.120 and
/// 301.200 is one glance with separators and a squint without them. The
/// value the form submits is the digits alone, so callers keep parsing what
/// they always did.
class PriceInputFormatter extends TextInputFormatter {
  const PriceInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    // A leading zero is a typo in a price, not a value.
    final value = int.tryParse(digits);
    if (value == null) return oldValue;
    final text = formatCountId(value);

    // The caret is kept a fixed number of *digits* from the end rather than
    // a fixed number of characters: inserting a separator two positions back
    // would otherwise walk it left as the number grows.
    final digitsAfterCaret = newValue.text
        .substring(newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'\D'), '')
        .length;

    var offset = text.length;
    var seen = 0;
    while (offset > 0 && seen < digitsAfterCaret) {
      offset--;
      if (RegExp(r'\d').hasMatch(text[offset])) seen++;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
