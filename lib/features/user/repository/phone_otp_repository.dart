import '../../../core/network/pokepedia_api.dart';

/// Phone verification, over pokepedia.id's `/api/otp/*` routes.
///
/// These two are the rare case where the app cannot talk to Supabase
/// directly: sending a code goes through Fazpass with a server-held key, and
/// verifying finishes with a `service_role` RPC. Both route handlers
/// authenticate with `getRequestAuth`, which accepts the app's bearer token,
/// so [PokepediaApi] can call them with the session already in hand.
class PhoneOtpRepository {
  PhoneOtpRepository(this._api);

  final PokepediaApi _api;

  /// Sends a code to [phone]. Returns the normalised number the server
  /// accepted, or throws with the server's own message.
  ///
  /// The number is passed as typed: `normalizeIndonesianPhone` runs on the
  /// server and is the authority on what "08xxx or +62xxx" means, so
  /// second-guessing it here could reject a number the server would take.
  Future<String> send(String phone) async {
    final json = await _api.post('/api/otp/send', {'phone': phone.trim()});
    return json['phone'] as String? ?? phone.trim();
  }

  /// Confirms [code] for [phone]. Throws with the server's message on a bad
  /// or expired code.
  Future<void> verify({required String phone, required String code}) {
    return _api.post('/api/otp/verify', {
      'phone': phone.trim(),
      'code': code.trim(),
    });
  }
}
