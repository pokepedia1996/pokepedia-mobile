import 'package:flutter/material.dart';

import '../../shared/models/card_condition.dart';
import 'app_theme.dart';

/// The 21 grading values from `listings_condition_check` bucketed into the
/// 7 `--cond-*` tokens in `globals.css`, mirroring how web's
/// `CONDITION_BADGE_CLASSES` / `CONDITION_CHART_VAR` collapse them.
const _top10 = {
  CardCondition.psa10,
  CardCondition.bgsGd10,
  CardCondition.cgc10,
  CardCondition.egs10,
};

const _nine = {
  CardCondition.psa9,
  CardCondition.bgs9,
  CardCondition.bgs95,
  CardCondition.cgc9,
  CardCondition.cgc95,
  CardCondition.egs9,
  CardCondition.egs95,
};

/// The badge/series color for [condition] — shared by [ConditionBadge], the
/// condition picker pills and the market activity chart so a condition reads
/// the same everywhere, like the web's shared condition color tokens.
Color conditionColorOf(BuildContext context, CardCondition condition) {
  final s = context.appSemantic;
  switch (condition) {
    case CardCondition.nm:
      return s.condNm;
    case CardCondition.lp:
      return s.condLp;
    case CardCondition.mp:
      return s.condMp;
    case CardCondition.hp:
      return s.condHp;
    default:
      if (_top10.contains(condition)) return s.condPsa10;
      if (_nine.contains(condition)) return s.condPsa9;
      return s.condPsaLow;
  }
}
