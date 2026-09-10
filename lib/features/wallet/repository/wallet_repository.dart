import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import 'models/wallet_models.dart';

/// Data access for the Wallet feature: `public.wallets` for the balance,
/// `get_wallet_activity` for the ledger, the
/// `*_withdrawal_destination(s)` RPCs for saved bank accounts, and
/// `/api/wallet/withdraw` for the payout itself.
///
/// The activity RPC rather than a direct `wallet_ledger` read: it already
/// buckets each row (penghasilan / refund / penarikan) and applies the
/// caller scoping, so the two clients agree on what a row means.
class WalletRepository {
  WalletRepository(this._client, this._api);

  final SupabaseClient _client;
  final PokepediaApi _api;

  Future<int> fetchBalance() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final row = await _client
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['balance'] as num?)?.toInt() ?? 0;
  }

  /// One page of the ledger. [beforeId] pages backwards from the oldest row
  /// already shown, which is how web's "Muat lebih banyak" walks it.
  Future<List<WalletActivity>> fetchActivity({
    WalletBucket bucket = WalletBucket.all,
    int limit = 20,
    int? beforeId,
  }) async {
    if (_client.auth.currentUser == null) return const [];
    final rows =
        await _client.rpc(
              'get_wallet_activity',
              params: {
                'p_limit': limit,
                'p_bucket': bucket.raw,
                'p_before_id': beforeId,
              },
            )
            as List;
    return rows
        .map((r) => WalletActivity.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<WithdrawalDestination>> fetchDestinations() async {
    if (_client.auth.currentUser == null) return const [];
    final rows = await _client.rpc('list_withdrawal_destinations') as List;
    return rows
        .map((r) => WithdrawalDestination.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Adds an account. Returns null on success, or the Indonesian message for
  /// the RPC's error code — web's `mapDestinationError`.
  Future<String?> addDestination({
    required String bankCode,
    required String accountNumber,
    required String accountHolderName,
    String? nickname,
    bool setDefault = false,
  }) async {
    try {
      await _client.rpc(
        'add_withdrawal_destination',
        params: {
          'p_bank_code': bankCode,
          'p_account_number': accountNumber,
          'p_account_holder_name': accountHolderName,
          'p_nickname': nickname,
          'p_set_default': setDefault,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return _destinationError(e.message);
    } catch (_) {
      return 'Gagal menyimpan rekening';
    }
  }

  Future<String?> updateDestination({
    required int id,
    required String bankCode,
    required String accountNumber,
    required String accountHolderName,
  }) async {
    try {
      await _client.rpc(
        'update_withdrawal_destination',
        params: {
          'p_id': id,
          'p_bank_code': bankCode,
          'p_account_number': accountNumber,
          'p_account_holder_name': accountHolderName,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return _destinationError(e.message);
    } catch (_) {
      return 'Gagal menyimpan rekening';
    }
  }

  Future<String?> setDefaultDestination(int id) async {
    try {
      await _client.rpc(
        'set_default_withdrawal_destination',
        params: {'p_id': id},
      );
      return null;
    } catch (_) {
      return 'Gagal mengatur default';
    }
  }

  Future<String?> deleteDestination(int id) async {
    try {
      await _client.rpc('delete_withdrawal_destination', params: {'p_id': id});
      return null;
    } catch (_) {
      return 'Gagal menghapus rekening';
    }
  }

  /// Requests a payout. Goes through the web route rather than Supabase
  /// because creating it needs the Xendit secret and the phone-verification
  /// gate that live on the server; the app authenticates with the Supabase
  /// session it already holds.
  ///
  /// Returns null on success, or a message to show.
  Future<String?> requestWithdrawal({
    required int amount,
    required int destinationId,
  }) async {
    try {
      await _api.post('/api/wallet/withdraw', {
        'amount': amount,
        'destination_id': destinationId,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Terjadi kesalahan jaringan';
    }
  }

  /// Ports `mapDestinationError` in `app/wallet/page.tsx` — the RPC raises
  /// codes, the screen shows sentences.
  String _destinationError(String message) {
    if (message.contains('invalid_account_number')) {
      return 'Nomor rekening tidak valid';
    }
    if (message.contains('invalid_holder_name')) {
      return 'Nama pemilik tidak boleh kosong';
    }
    if (message.contains('invalid_bank_code')) return 'Pilih bank';
    if (message.contains('duplicate_destination')) {
      return 'Rekening ini sudah tersimpan';
    }
    if (message.contains('destination_not_found')) {
      return 'Rekening tidak ditemukan';
    }
    if (message.contains('unauthorized')) return 'Sesi habis, login ulang';
    return 'Gagal menyimpan rekening';
  }
}
