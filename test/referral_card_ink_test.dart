import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/referral/presentation/referral_card_ink.dart';
import 'package:pokepedia_mobile/features/referral/repository/models/referral_models.dart';

void main() {
  test('design ink export parses for every tier', () {
    final ink = parseCardInk(
      File('assets/data/referral_card_ink.json').readAsStringSync(),
    );
    expect(ink.keys, ReferralTierKey.values);
    expect(ink[ReferralTierKey.biasa]!.extras, isEmpty);
    expect(ink[ReferralTierKey.jackpot]!.extras, hasLength(4));
    expect(ink[ReferralTierKey.langka]!.word, 'Langka!');
    final loop = ink[ReferralTierKey.langka]!.loop.getBounds();
    expect(loop.left, closeTo(19, 8));
    expect(loop.width, greaterThan(80));
  });

  test('parseScribblePath reads M, L, Q and Z', () {
    final b = parseScribblePath('M0 -7 Q0 0 7 0 L0 7 Z').getBounds();
    expect(b.top, -7);
    expect(b.right, 7);
    expect(b.bottom, 7);
  });

  test('timeline: footer waits for the count-up, extras extend the total', () {
    const plain = CardTimeline(countMs: 900, extras: 0);
    const jackpot = CardTimeline(countMs: 1300, extras: 4);
    expect(plain.countEnd, 1440);
    expect(plain.total, 1860);
    expect(jackpot.total, 1840 + 420 + 3 * 150 + 260);
  });
}
