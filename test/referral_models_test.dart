import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/referral/repository/models/referral_models.dart';

// Payloads are the real local-DB output quoted in 09-backend-siap.md §3.
void main() {
  group('ReferralDashboard.fromJson', () {
    final raw = {
      'enabled': true,
      'code': 'USER1653',
      'link': 'https://pokepedia.id/r/USER1653',
      'coupon': {'max_amount': 10000, 'min_subtotal': 30000},
      'koin_balance': 30000,
      'stats': {'koin_earned': 25000, 'friends': 10, 'packs': 4},
      'counts': {'all': 10, 'process': 4, 'packs': 4},
      'ready_packs': [
        {
          'id': 'p6',
          'from_username': 'ref_test_6',
          'created_at': '2026-11-02T09:20:52Z',
        },
        {
          'id': 'p5',
          'from_username': 'ref_test_5',
          'created_at': '2026-11-04T09:20:52Z',
        },
      ],
      'friends': [
        {
          'referee_id': 'r1',
          'username': 'ref_test_1',
          'avatar_url': null,
          'status': 'registered',
          'pack': null,
          'can_remind': true,
          'next_remind_at': null,
        },
        {
          'referee_id': 'r3',
          'username': 'ref_test_3',
          'status': 'first_order_paid',
          'pack': null,
          'can_remind': false,
        },
        {
          'referee_id': 'r8',
          'username': 'ref_test_8',
          'status': 'completed',
          'pack': {
            'id': 'p8',
            'status': 'opened',
            'tier': 'langka',
            'character': 'gengar',
            'amount': 25000,
          },
        },
        {
          'referee_id': 'rx',
          'username': 'rejected',
          'status': 'completed',
          'pack': {'id': 'px', 'status': 'void'},
        },
      ],
      'has_more': false,
      'tiers': [
        {
          'key': 'biasa',
          'odds': 70,
          'amount': 5000,
          'pool': ['eevee'],
        },
        {
          'key': 'jackpot',
          'odds': 2.5,
          'amount': 50000,
          'pool': ['pikachu'],
        },
      ],
    };

    test('reads every field the dashboard shows', () {
      final d = ReferralDashboard.fromJson(raw);
      expect(d.enabled, isTrue);
      expect(d.code, 'USER1653');
      expect(d.couponMaxAmount, 10000);
      expect(d.couponMinSubtotal, 30000);
      expect(d.koinEarned, 25000);
      expect(d.friendCount, 10);
      expect(d.packCount, 4);
      expect(d.counts[ReferralFilter.process], 4);
      expect(d.readyPacks.map((p) => p.fromUsername), [
        'ref_test_6',
        'ref_test_5',
      ]);
      expect(d.friends, hasLength(4));
    });

    test('maps friend states and progress segments', () {
      final f = ReferralDashboard.fromJson(raw).friends;
      expect(f[0].status, ReferralFriendStatus.registered);
      expect(f[0].canRemind, isTrue);
      expect(f[0].progress, 1);
      expect(f[1].progress, 2);
      expect(f[2].pack!.tier, ReferralTierKey.langka);
      expect(f[2].pack!.amount, 25000);
      expect(f[2].progress, 3);
      // A rejected pack reads as not eligible, so back to one segment.
      expect(f[3].pack!.status, ReferralPackStatus.voided);
      expect(f[3].progress, 1);
    });

    test('sorts tiers largest first and keeps fractional odds', () {
      final tiers = ReferralDashboard.fromJson(raw).tiers;
      expect(tiers.first.key, ReferralTierKey.jackpot);
      expect(tiers.first.odds, 2.5);
    });

    test('throws the in-JSON error code', () {
      expect(
        () => ReferralDashboard.fromJson({'error': 'invalid_filter'}),
        throwsA(
          isA<ReferralException>().having(
            (e) => e.code,
            'code',
            'invalid_filter',
          ),
        ),
      );
    });
  });

  test('PackResult reads the roll and surfaces pack errors', () {
    final r = PackResult.fromJson({
      'id': 'p6',
      'tier': 'langka',
      'amount': 25000,
      'character': 'gengar',
      'opened_at': '2026-11-10T09:21:25Z',
      'from_username': 'ref_test_6',
      'koin_balance': 55000,
    });
    expect(r.tier, ReferralTierKey.langka);
    expect(r.koinBalance, 55000);
    expect(
      () => PackResult.fromJson({'error': 'pack_held'}),
      throwsA(
        isA<ReferralException>().having(
          (e) => e.message,
          'message',
          'Pack ini menunggu verifikasi.',
        ),
      ),
    );
  });

  test('RemindResult: ok false is a soft refusal, not an error', () {
    expect(
      RemindResult.fromJson({
        'ok': false,
        'next_allowed_at': '2026-11-12T09:20:52Z',
      }).ok,
      isFalse,
    );
    expect(
      () => RemindResult.fromJson({'error': 'not_remindable'}),
      throwsA(isA<ReferralException>()),
    );
  });

  test('KoinBalance with and without a pending expiry', () {
    final b = KoinBalance.fromJson({
      'balance': 30000,
      'next_expiry': {'amount': 5000, 'at': '2026-11-15T09:20:52Z'},
    });
    expect(b.balance, 30000);
    expect(b.nextExpiryAmount, 5000);
    expect(
      KoinBalance.fromJson({'balance': 0, 'next_expiry': null}).nextExpiryAt,
      isNull,
    );
  });

  test('KoinHistoryPage labels rows and shows expiry only on live lots', () {
    final page = KoinHistoryPage.fromJson({
      'rows': [
        {
          'id': 6,
          'delta': 5000,
          'reason': 'admin',
          'expires_at': '2026-11-15T09:20:52Z',
          'remaining': 5000,
          'balance_after': 30000,
        },
        {
          'id': 7,
          'delta': -5000,
          'reason': 'checkout_spend',
          'expires_at': '2026-11-15T09:20:52Z',
          'remaining': null,
          'balance_after': 25000,
        },
      ],
      'has_more': false,
    });
    expect(page.rows.map((r) => r.label), [
      'Koin dari Pokepedia',
      'Dipakai belanja',
    ]);
    expect(page.rows[0].showsExpiry, isTrue);
    expect(page.rows[1].showsExpiry, isFalse);
  });
}
