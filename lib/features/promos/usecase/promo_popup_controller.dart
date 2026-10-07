import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/promo_popup.dart';
import '../repository/promo_repository.dart';
import '../utils/popup_state.dart';
import '../utils/select_popup.dart';

export '../repository/models/promo_popup.dart';

final promoRepositoryProvider = Provider(
  (ref) => PromoRepository(
    ref.read(supabaseClientProvider),
    ref.read(pokepediaApiProvider),
  ),
);

/// Ports the decision half of web's `usePromoPopup`: which campaign, if any,
/// this app run shows, and the frequency record each outcome leaves behind.
///
/// One attempt per app run. Web re-evaluates per navigation until something
/// shows, but the app has one home screen, and the per-campaign cooldown in
/// the persisted record is the real frequency rule either way.
class PromoPopupController {
  PromoPopupController(this._repository, {int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PromoRepository _repository;
  final int Function() _clock;

  bool _attempted = false;

  /// Whether this run has already had its chance at a popup.
  bool get attempted => _attempted;

  /// The campaign to show now, or null. Spends this run's attempt.
  Future<PromoPopup?> pick({required bool isAuthed}) async {
    if (_attempted) return null;
    _attempted = true;
    try {
      final popups = await _repository.fetchLivePopups();
      if (popups.isEmpty) return null;
      final state = await _repository.readState();
      return selectPopup(popups, state, now: _clock(), isAuthed: isAuthed);
    } catch (error) {
      debugPrint('[promos] failed to load popups: $error');
      return null;
    }
  }

  /// Gives back an attempt that was spent on a popup the screen could not
  /// show after all (the creative 404'd, the user left the tab), so a later
  /// visit can try again — web's `resolvedRef` staying false.
  void release() => _attempted = false;

  /// Web's `recordShown` + the impression event.
  Future<void> recordShown(PromoPopup popup) async {
    final state = await _repository.readState();
    await _repository.writeState(
      withShown(state, popup.slug, popup.cooldownHours, _clock()),
    );
    await _repository.logEvent(popup.id, PromoPopupEvent.impression);
  }

  /// Web's `recordDismissed` + the dismiss event.
  Future<void> recordDismissed(PromoPopup popup) async {
    final state = await _repository.readState();
    await _repository.writeState(withDismissed(state, popup.slug, _clock()));
    await _repository.logEvent(popup.id, PromoPopupEvent.dismiss);
  }

  /// Web's `recordClicked` + the click event.
  Future<void> recordClicked(PromoPopup popup) async {
    final state = await _repository.readState();
    await _repository.writeState(withClicked(state, popup.slug, _clock()));
    await _repository.logEvent(popup.id, PromoPopupEvent.click);
  }
}

final promoPopupControllerProvider = Provider(
  (ref) => PromoPopupController(ref.read(promoRepositoryProvider)),
);
