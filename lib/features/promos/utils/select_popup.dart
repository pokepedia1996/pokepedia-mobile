import '../repository/models/promo_popup.dart';
import 'popup_state.dart';

bool _audienceMatches(PromoPopup popup, bool isAuthed) {
  if (popup.audience == PromoAudience.all) return true;
  return (popup.audience == PromoAudience.authed) == isAuthed;
}

bool _isEligible(
  PromoPopup popup,
  PopupState state, {
  required int now,
  required bool isAuthed,
}) {
  final seen = state[popup.slug];
  final maxImpressions = popup.maxImpressions;
  return popup.startsAt <= now &&
      now < popup.endsAt &&
      _audienceMatches(popup, isAuthed) &&
      seen?.clickedAt == null &&
      (seen?.dismissCount ?? 0) < popup.maxDismissals &&
      (maxImpressions == null || (seen?.shownCount ?? 0) < maxImpressions) &&
      now >= (seen?.snoozedUntil ?? 0);
}

/// Ports web's `selectPopup` (`features/promos/utils/select-popup.ts`): the
/// highest-priority eligible campaign, the newer one on a tie.
PromoPopup? selectPopup(
  List<PromoPopup> popups,
  PopupState state, {
  required int now,
  required bool isAuthed,
}) {
  PromoPopup? best;
  for (final candidate in popups) {
    if (!_isEligible(candidate, state, now: now, isAuthed: isAuthed)) continue;
    if (best == null ||
        candidate.priority > best.priority ||
        (candidate.priority == best.priority &&
            candidate.startsAt > best.startsAt)) {
      best = candidate;
    }
  }
  return best;
}
