import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/user/utils/delete_account_errors.dart';

/// Ports `features/account/utils/delete-account-errors.test.ts`: every code
/// `delete_my_account` raises reads as web's copy, and only the four
/// in-flight-money refusals count as expected.
void main() {
  test('each refusal maps to web copy', () {
    expect(
      translateDeleteAccountError('wallet_not_empty'),
      'Tarik saldo dompet kamu dulu sebelum menghapus akun.',
    );
    expect(
      translateDeleteAccountError('withdrawal_in_progress'),
      'Tunggu penarikan saldo selesai dulu.',
    );
    expect(
      translateDeleteAccountError('has_active_orders'),
      'Selesaikan semua pesanan yang sedang berjalan dulu.',
    );
    expect(
      translateDeleteAccountError('has_pending_payment'),
      'Masih ada pembayaran yang diproses. Coba lagi nanti.',
    );
  });

  test('unauthorized asks the user to sign in again', () {
    expect(
      translateDeleteAccountError('unauthorized'),
      'Sesi kamu berakhir. Masuk lagi untuk menghapus akun.',
    );
  });

  test('an unknown error falls back to a generic message', () {
    expect(
      translateDeleteAccountError('listing_cleanup_failed:not_found'),
      'Gagal menghapus akun. Coba lagi.',
    );
  });

  test('only the four refusals are treated as expected', () {
    for (final code in [
      'wallet_not_empty',
      'withdrawal_in_progress',
      'has_active_orders',
      'has_pending_payment',
    ]) {
      expect(isDeleteAccountRefusal(code), isTrue, reason: code);
    }
    expect(isDeleteAccountRefusal('unauthorized'), isFalse);
    expect(isDeleteAccountRefusal('boom'), isFalse);
  });

  test('confirmation word matches web', () {
    expect(deleteAccountConfirmationWord, 'HAPUS');
  });
}
