import 'package:flutter/material.dart';

/// Brand color scales ported from `pokepedia-web/app/globals.css`.
/// Each family follows the web's 10/20/.../100 ramp plus the bare
/// (~500-weight) value, converted from OKLCH to sRGB.
class AppColors {
  AppColors._();

  // Brand black (neutral) ramp.
  static const black10 = Color(0xFFD9D6D6);
  static const black20 = Color(0xFFBEB7B9);
  static const black30 = Color(0xFF9C9296);
  static const black40 = Color(0xFF787074);
  static const black50 = Color(0xFF544D50);
  static const black = Color(0xFF2B2528);
  static const black60 = Color(0xFF272226);
  static const black70 = Color(0xFF221F21);
  static const black80 = Color(0xFF1E1B1D);
  static const black90 = Color(0xFF191718);
  static const black100 = Color(0xFF141313);

  // Brand red (primary).
  static const red10 = Color(0xFFF2D3CD);
  static const red20 = Color(0xFFE9B6AC);
  static const red30 = Color(0xFFDD9385);
  static const red40 = Color(0xFFD06F5C);
  static const red50 = Color(0xFFC1492F);
  static const red = Color(0xFFB0270A);
  static const red60 = Color(0xFF992409);
  static const red70 = Color(0xFF7F1F09);
  static const red80 = Color(0xFF671A08);
  static const red90 = Color(0xFF4C1406);
  static const red100 = Color(0xFF340D03);

  // Brand cream (background/surface).
  static const cream10 = Color(0xFFFCFAF6);
  static const cream20 = Color(0xFFFAF6EE);
  static const cream30 = Color(0xFFF7F1E4);
  static const cream40 = Color(0xFFF3EAD6);
  static const cream50 = Color(0xFFF0E4CA);
  static const cream = Color(0xFFEDDEBD);
  static const cream60 = Color(0xFFCFC2A6);
  static const cream70 = Color(0xFFAEA38C);
  static const cream80 = Color(0xFF8C8371);
  static const cream90 = Color(0xFF696357);
  static const cream100 = Color(0xFF484440);

  // Brand green (success / WTS-ask).
  static const green10 = Color(0xFFDFF4E4);
  static const green20 = Color(0xFFC3ECCE);
  static const green30 = Color(0xFFA3E3B4);
  static const green40 = Color(0xFF83D99A);
  static const green50 = Color(0xFF6DD389);
  static const green = Color(0xFF54D477);
  static const green60 = Color(0xFF3FB863);
  static const green70 = Color(0xFF2D9A50);
  static const green80 = Color(0xFF1F7C3E);
  static const green90 = Color(0xFF135D2D);
  static const green100 = Color(0xFF0A421F);

  // Brand blue (bid/WTB).
  static const blue10 = Color(0xFFDCEEF7);
  static const blue20 = Color(0xFFBEE1F1);
  static const blue30 = Color(0xFF9CD3EB);
  static const blue40 = Color(0xFF79C5E4);
  static const blue50 = Color(0xFF66BDE1);
  static const blue = Color(0xFF52B4DD);
  static const blue60 = Color(0xFF389DC6);
  static const blue70 = Color(0xFF2A81A5);
  static const blue80 = Color(0xFF1E6684);
  static const blue90 = Color(0xFF144C63);
  static const blue100 = Color(0xFF0D3644);

  // Brand gold (PSA10 / premium).
  static const gold10 = Color(0xFFFFEAC2);
  static const gold20 = Color(0xFFFAD68F);
  static const gold30 = Color(0xFFF2C066);
  static const gold40 = Color(0xFFE9AA47);
  static const gold50 = Color(0xFFDF9631);
  static const gold = Color(0xFFD4831F);
  static const gold60 = Color(0xFFB56D18);
  static const gold70 = Color(0xFF915714);
  static const gold80 = Color(0xFF71430F);
  static const gold90 = Color(0xFF52300A);
  static const gold100 = Color(0xFF362006);
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
    condNm: AppColors.condNm,
    condLp: AppColors.condLp,
    condMp: AppColors.condMp,
    condHp: AppColors.condHp,
    condPsaLow: AppColors.condPsaLow,
    condPsa9: AppColors.condPsa9,
    condPsa10: AppColors.condPsa10,
  );

  static const dark = light;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? bid,
    Color? ask,
    Color? gold,
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
