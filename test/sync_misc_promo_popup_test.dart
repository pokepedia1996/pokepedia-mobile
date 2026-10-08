import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/promos/repository/models/promo_popup.dart';
import 'package:pokepedia_mobile/features/promos/utils/popup_state.dart';
import 'package:pokepedia_mobile/features/promos/utils/select_popup.dart';

const now = 1700000000000;
const hour = 60 * 60 * 1000;

PromoPopup popup({
  int id = 1,
  String slug = 'gratis-ongkir',
  PromoAudience audience = PromoAudience.all,
  num priority = 0,
  int cooldownHours = 24,
  int? maxImpressions,
  int maxDismissals = 3,
  int startsAt = now - hour,
  int endsAt = now + hour,
}) => PromoPopup(
  id: id,
  slug: slug,
  title: 'Gratis Ongkir',
  imageUrl: 'https://cdn.pokepedia.id/promo/a.webp',
  imageAlt: 'promo',
  ctaLabel: 'Belanja Sekarang',
  ctaUrl: '/market',
  audience: audience,
  priority: priority,
  cooldownHours: cooldownHours,
  maxImpressions: maxImpressions,
  maxDismissals: maxDismissals,
  startsAt: startsAt,
  endsAt: endsAt,
);

Map<String, dynamic> validRow([Map<String, dynamic> overrides = const {}]) => {
  'id': 3,
  'slug': 'gratis-ongkir-sept-2026',
  'title': 'Gratis Ongkir',
  'image_url': 'https://cdn2.pokepedia.id/media/promo-1.webp',
  'image_alt': 'Promo gratis ongkir',
  'cta_label': 'Belanja Sekarang',
  'cta_url': '/market',
  'audience': 'all',
  'priority': 10,
  'cooldown_hours': 4,
  'max_impressions': null,
  'max_dismissals': 3,
  'starts_at': '2026-09-15T00:00:00+07:00',
  'ends_at': '2026-09-30T23:59:59+07:00',
  ...overrides,
};

PromoPopup? pick(
  List<PromoPopup> popups,
  PopupState state, {
  bool authed = false,
}) => selectPopup(popups, state, now: now, isAuthed: authed);

void main() {
  group('selectPopup', () {
    test('returns a live campaign no one has seen', () {
      expect(pick([popup()], {})?.slug, 'gratis-ongkir');
    });

    test('skips campaigns outside their window', () {
      expect(pick([popup(startsAt: now + 1)], {}), isNull);
      expect(pick([popup(endsAt: now)], {}), isNull);
    });

    test('honours the audience', () {
      expect(pick([popup(audience: PromoAudience.authed)], {}), isNull);
      expect(
        pick([popup(audience: PromoAudience.authed)], {}, authed: true),
        isNotNull,
      );
      expect(
        pick([popup(audience: PromoAudience.anon)], {}, authed: true),
        isNull,
      );
    });

    test('a shown campaign is snoozed for its cooldown', () {
      final state = withShown({}, 'gratis-ongkir', 24, now);
      expect(pick([popup()], state), isNull);
      expect(
        selectPopup(
          [popup(endsAt: now + 48 * hour)],
          state,
          now: now + 24 * hour,
          isAuthed: false,
        ),
        isNotNull,
      );
    });

    test('stops after max dismissals and max impressions', () {
      var state = withShown({}, 'gratis-ongkir', 24, now - 48 * hour);
      for (var i = 0; i < 3; i++) {
        state = withDismissed(state, 'gratis-ongkir', now);
      }
      expect(pick([popup()], state), isNull);

      final shownTwice = {
        'gratis-ongkir': const PopupSlugState(shownCount: 2, lastShownAt: now),
      };
      expect(pick([popup(maxImpressions: 2)], shownTwice), isNull);
      expect(pick([popup(maxImpressions: 3)], shownTwice), isNotNull);
    });

    test('a clicked campaign never shows again', () {
      final state = withClicked({}, 'gratis-ongkir', now - 10 * hour);
      expect(pick([popup()], state), isNull);
    });

    test('highest priority wins, newest on a tie', () {
      final picked = pick([
        popup(id: 1, slug: 'a', priority: 1),
        popup(id: 2, slug: 'b', priority: 5),
        popup(id: 3, slug: 'c', priority: 5, startsAt: now - hour + 1),
      ], {});
      expect(picked?.slug, 'c');
    });
  });

  group('popup state', () {
    test('withShown counts and snoozes', () {
      final state = withShown(withShown({}, 's', 4, now), 's', 4, now + 1);
      expect(state['s']!.shownCount, 2);
      expect(state['s']!.lastShownAt, now + 1);
      expect(state['s']!.snoozedUntil, now + 1 + 4 * hour);
    });

    test('round-trips through JSON', () {
      final state = withClicked(withShown({}, 's', 4, now), 's', now);
      final decoded = parsePopupState(encodePopupState(state));
      expect(decoded['s']!.shownCount, 1);
      expect(decoded['s']!.clickedAt, now);
    });

    test('a malformed blob reads as a fresh device', () {
      expect(parsePopupState('nope'), isEmpty);
      expect(
        parsePopupState({
          's': {'shownCount': -1},
        }),
        isEmpty,
      );
    });

    test('prunes entries untouched for the retention window', () {
      final stale = {
        'old': const PopupSlugState(shownCount: 1, lastShownAt: 0),
      };
      final pruned = withShown(stale, 'new', 4, popupEntryRetentionMs + 1);
      expect(pruned.containsKey('old'), isFalse);
      expect(pruned.containsKey('new'), isTrue);
    });
  });

  group('sanitizeCtaUrl', () {
    test('keeps same-origin paths and https URLs', () {
      expect(sanitizeCtaUrl('/market'), '/market');
      expect(sanitizeCtaUrl('/market?q=pikachu#top'), '/market?q=pikachu#top');
      expect(sanitizeCtaUrl('https://example.com/a'), 'https://example.com/a');
    });

    test('rejects off-origin paths and other schemes', () {
      expect(sanitizeCtaUrl('//evil.com'), isNull);
      expect(sanitizeCtaUrl(r'/\evil.com'), isNull);
      expect(sanitizeCtaUrl('http://example.com'), isNull);
      expect(sanitizeCtaUrl('javascript:alert(1)'), isNull);
      expect(sanitizeCtaUrl('market'), isNull);
    });
  });

  group('PromoPopup.fromRow', () {
    test('maps a valid row', () {
      final parsed = PromoPopup.fromRow(validRow());
      expect(parsed, isNotNull);
      expect(parsed!.slug, 'gratis-ongkir-sept-2026');
      expect(parsed.isInternalTarget, isTrue);
      expect(parsed.maxImpressions, isNull);
    });

    test('proxies R2 hosts onto the CDN', () {
      final parsed = PromoPopup.fromRow(
        validRow({
          'image_url':
              'https://pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev/media/p.webp',
        }),
      );
      expect(parsed!.imageUrl, 'https://cdn2.pokepedia.id/media/p.webp');
    });

    test('drops rows with an unsafe CTA, foreign image or bad fields', () {
      expect(PromoPopup.fromRow(validRow({'cta_url': '//evil.com'})), isNull);
      expect(
        PromoPopup.fromRow(validRow({'image_url': 'https://evil.com/a.webp'})),
        isNull,
      );
      expect(PromoPopup.fromRow(validRow({'audience': 'everyone'})), isNull);
      expect(PromoPopup.fromRow(validRow({'cooldown_hours': 0})), isNull);
      expect(PromoPopup.fromRow(validRow({'starts_at': 'soon'})), isNull);
    });
  });
}
