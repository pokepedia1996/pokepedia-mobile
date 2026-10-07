import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/pokepedia_api.dart';
import '../utils/popup_state.dart';
import 'models/promo_popup.dart';

/// What a popup reports back — web's `PromoPopupEvent`.
enum PromoPopupEvent { impression, click, dismiss }

const _popupColumns =
    'id, slug, title, image_url, image_alt, cta_label, cta_url, audience, '
    'priority, cooldown_hours, max_impressions, max_dismissals, starts_at, '
    'ends_at';

/// Same key as web's `STORAGE_KEY`, so the record reads the same if it is
/// ever compared across clients.
const _stateKey = 'pokepedia:promo-popup:v1';

/// Data access for interstitial campaigns. Ports
/// `features/promos/api/promos.client.ts` and `promo-events.client.ts`.
///
/// `promo_popups` is readable by `anon` and `authenticated`, and its RLS
/// policy already limits rows to active ones inside their window.
/// `promo_popup_events` is service-role only, so events go through web's
/// `/api/promos/events` route like they do from the browser.
class PromoRepository {
  PromoRepository(this._client, this._api);

  final SupabaseClient _client;
  final PokepediaApi _api;

  Future<List<PromoPopup>> fetchLivePopups() async {
    final rows = await _client
        .from('promo_popups')
        .select(_popupColumns)
        .order('priority', ascending: false)
        .order('starts_at', ascending: false);
    final origins = {...promoImageOrigins, ..._ownSupabaseOrigin()};
    return [
      for (final row in rows)
        ?PromoPopup.fromRow(row, allowedImageOrigins: origins),
    ];
  }

  /// Web's `LOCAL_SUPABASE_ORIGIN`, generalised: whichever project this
  /// build signs in to may host creatives in its own storage.
  Set<String> _ownSupabaseOrigin() {
    final uri = Uri.tryParse(AppConfig.supabaseUrl);
    if (uri == null || uri.host.isEmpty) return const {};
    if (uri.scheme != 'https' && uri.scheme != 'http') return const {};
    return {uri.origin};
  }

  /// Best-effort, like web's `sendBeacon`: a lost event never touches the
  /// popup.
  ///
  /// Only sent with a session — [PokepediaApi] authenticates every call, and
  /// sending one signed out would spend a refresh attempt on a session that
  /// does not exist.
  Future<void> logEvent(int popupId, PromoPopupEvent event) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _api.post('/api/promos/events', {
        'popupId': popupId,
        'event': event.name,
      });
    } on ApiException catch (error) {
      // The route answers 204 with no body, which the client reports as an
      // unrecognised response; anything else is a genuinely lost event.
      if (error.statusCode == 204) return;
      debugPrint('[promos] event ${event.name} failed: ${error.message}');
    } catch (error) {
      debugPrint('[promos] event ${event.name} failed: $error');
    }
  }

  /// Web's `readPopupState`. An unreadable store is a fresh device.
  Future<PopupState> readState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stateKey);
      if (raw == null) return {};
      return parsePopupState(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  /// Web's `writePopupState` storage half; [state] is already pruned.
  Future<void> writeState(PopupState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stateKey, jsonEncode(encodePopupState(state)));
    } catch (error) {
      debugPrint('[promos] failed to persist popup state: $error');
    }
  }
}
