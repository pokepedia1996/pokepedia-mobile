import 'package:flutter/material.dart';

/// Brand color scales ported from `pokepedia-web/app/globals.css`.
/// Each family follows the web's 10/20/.../100 ramp plus the bare
/// (~500-weight) value, converted from OKLCH to sRGB.
///
/// Regenerated from the `--color-brand-*` tokens with a checked OKLCH
/// conversion: all 66 values had drifted from the site, red worst of all
/// (`red` was #B0270A against the site's #B33B3B — an orange cast where web
/// has equal green and blue). `colour_palette_test` recomputes the whole
/// ramp from those tokens, so a mis-converted value fails the build rather
/// than shipping as a slightly-wrong brand.
class AppColors {
  AppColors._();

  // Brand black (neutral) ramp.
  static const black10 = Color(0xFFD1D0D0);
  static const black20 = Color(0xFFB3B0B1);
  static const black30 = Color(0xFF8D898A);
  static const black40 = Color(0xFF676162);
  static const black50 = Color(0xFF41393B);
  static const black = Color(0xFF1B1214);
  static const black60 = Color(0xFF170F11);
  static const black70 = Color(0xFF120C0D);
  static const black80 = Color(0xFF0E090A);
  static const black90 = Color(0xFF090607);
  static const black100 = Color(0xFF050404);

  // Brand red (primary).
  static const red10 = Color(0xFFF0D8D8);
  static const red20 = Color(0xFFE6BEBE);
  static const red30 = Color(0xFFD99D9D);
  static const red40 = Color(0xFFCC7C7C);
  static const red50 = Color(0xFFC05C5C);
  static const red = Color(0xFFB33B3B);
  static const red60 = Color(0xFF953131);
  static const red70 = Color(0xFF772727);
  static const red80 = Color(0xFF5A1E1E);
  static const red90 = Color(0xFF3C1414);
  static const red100 = Color(0xFF240C0C);

  // Brand cream (background/surface).
  static const cream10 = Color(0xFFFBFAF6);
  static const cream20 = Color(0xFFF9F7EF);
  static const cream30 = Color(0xFFF6F3E8);
  static const cream40 = Color(0xFFF2EEE0);
  static const cream50 = Color(0xFFEFEAD8);
  static const cream = Color(0xFFECE6D0);
  static const cream60 = Color(0xFFC5C0AD);
  static const cream70 = Color(0xFF9D998B);
  static const cream80 = Color(0xFF767368);
  static const cream90 = Color(0xFF4F4D45);
  static const cream100 = Color(0xFF2F2E2A);

  // Brand green (success / WTS-ask).
  static const green10 = Color(0xFFD8F5E1);
  static const green20 = Color(0xFFB5ECC7);
  static const green30 = Color(0xFF8EE2AA);
  static const green40 = Color(0xFF67D88C);
  static const green50 = Color(0xFF4FD07A);
  static const green = Color(0xFF3AD568);
  static const green60 = Color(0xFF2FB256);
  static const green70 = Color(0xFF258E45);
  static const green80 = Color(0xFF1C6B34);
  static const green90 = Color(0xFF124723);
  static const green100 = Color(0xFF0A2B15);

  // Brand blue (bid/WTB).
  static const blue10 = Color(0xFFDDF0FA);
  static const blue20 = Color(0xFFBDE2F5);
  static const blue30 = Color(0xFF99D2EF);
  static const blue40 = Color(0xFF79C5E9);
  static const blue50 = Color(0xFF69BFE7);
  static const blue = Color(0xFF59BAE4);
  static const blue60 = Color(0xFF4A9BBF);
  static const blue70 = Color(0xFF3B7C98);
  static const blue80 = Color(0xFF2D5D72);
  static const blue90 = Color(0xFF1E3E4C);
  static const blue100 = Color(0xFF12252E);

  // Brand gold (PSA10 / premium).
  static const gold10 = Color(0xFFFFED78);
  static const gold20 = Color(0xFFFFDC67);
  static const gold30 = Color(0xFFFFCC55);
  static const gold40 = Color(0xFFF0BB42);
  static const gold50 = Color(0xFFDFAB2C);
  static const gold = Color(0xFFD4A017);
  static const gold60 = Color(0xFFB88600);
  static const gold70 = Color(0xFF966400);
  static const gold80 = Color(0xFF774700);
  static const gold90 = Color(0xFF572800);
  static const gold100 = Color(0xFF3A0B00);
  static const goldLight = Color(0xFFEBBA5F);
  static const goldDark = Color(0xFF8C6112);

  // Condition badge colors (buyer-facing card condition pills).
  static const condNm = Color(0xFF2AB37E);
  static const condLp = Color(0xFF3C7CE0);
  static const condMp = Color(0xFFE0A62E);
  static const condHp = Color(0xFFE0742E);
  static const condPsaLow = Color(0xFFE0303C);
  static const condPsa9 = Color(0xFF8352D6);
  static const condPsa10 = gold;
}

class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.bid,
    required this.ask,
    required this.gold,
    required this.chatMine,
    required this.chatTheirs,
    required this.condNm,
    required this.condLp,
    required this.condMp,
    required this.condHp,
    required this.condPsaLow,
    required this.condPsa9,
    required this.condPsa10,
  });

  final Color success;
  final Color bid;
  final Color ask;
  final Color gold;

  /// Chat bubbles. Web paints its own `bg-green-100` and the other party's
  /// `bg-blue-50`, with `green-900/30` and `slate-700` after dark — a pair
  /// light enough to read dark text on, which is why they aren't the brand
  /// primary/secondary the bubbles used to borrow.
  final Color chatMine;
  final Color chatTheirs;

  final Color condNm;
  final Color condLp;
  final Color condMp;
  final Color condHp;
  final Color condPsaLow;
  final Color condPsa9;
  final Color condPsa10;

  static const light = AppSemanticColors(
    success: AppColors.green70,
    bid: AppColors.blue70,
    ask: AppColors.green70,
    gold: AppColors.gold,
    chatMine: AppColors.green10,
    chatTheirs: AppColors.blue10,
    condNm: AppColors.condNm,
    condLp: AppColors.condLp,
    condMp: AppColors.condMp,
    condHp: AppColors.condHp,
    condPsaLow: AppColors.condPsaLow,
    condPsa9: AppColors.condPsa9,
    condPsa10: AppColors.condPsa10,
  );

  /// Everything the light set has, with the two chat bubbles darkened —
  /// `green10`/`blue10` on a dark surface glare, and web swaps them too.
  static const dark = AppSemanticColors(
    success: AppColors.green70,
    bid: AppColors.blue70,
    ask: AppColors.green70,
    gold: AppColors.gold,
    chatMine: AppColors.green90,
    chatTheirs: AppColors.blue90,
    condNm: AppColors.condNm,
    condLp: AppColors.condLp,
    condMp: AppColors.condMp,
    condHp: AppColors.condHp,
    condPsaLow: AppColors.condPsaLow,
    condPsa9: AppColors.condPsa9,
    condPsa10: AppColors.condPsa10,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? bid,
    Color? ask,
    Color? gold,
    Color? chatMine,
    Color? chatTheirs,
    Color? condNm,
    Color? condLp,
    Color? condMp,
    Color? condHp,
    Color? condPsaLow,
    Color? condPsa9,
    Color? condPsa10,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      bid: bid ?? this.bid,
      ask: ask ?? this.ask,
      gold: gold ?? this.gold,
      chatMine: chatMine ?? this.chatMine,
      chatTheirs: chatTheirs ?? this.chatTheirs,
      condNm: condNm ?? this.condNm,
      condLp: condLp ?? this.condLp,
      condMp: condMp ?? this.condMp,
      condHp: condHp ?? this.condHp,
      condPsaLow: condPsaLow ?? this.condPsaLow,
      condPsa9: condPsa9 ?? this.condPsa9,
      condPsa10: condPsa10 ?? this.condPsa10,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      bid: Color.lerp(bid, other.bid, t)!,
      ask: Color.lerp(ask, other.ask, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      chatMine: Color.lerp(chatMine, other.chatMine, t)!,
      chatTheirs: Color.lerp(chatTheirs, other.chatTheirs, t)!,
      condNm: Color.lerp(condNm, other.condNm, t)!,
      condLp: Color.lerp(condLp, other.condLp, t)!,
      condMp: Color.lerp(condMp, other.condMp, t)!,
      condHp: Color.lerp(condHp, other.condHp, t)!,
      condPsaLow: Color.lerp(condPsaLow, other.condPsaLow, t)!,
      condPsa9: Color.lerp(condPsa9, other.condPsa9, t)!,
      condPsa10: Color.lerp(condPsa10, other.condPsa10, t)!,
    );
  }
}
