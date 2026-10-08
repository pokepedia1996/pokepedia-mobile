/// The refusals `delete_my_account` raises while money or an order is still
/// in flight — `REFUSAL_MESSAGES` in
/// `features/account/utils/delete-account-errors.ts`.
const _refusalMessages = {
  'wallet_not_empty': 'Tarik saldo dompet kamu dulu sebelum menghapus akun.',
  'withdrawal_in_progress': 'Tunggu penarikan saldo selesai dulu.',
  'has_active_orders': 'Selesaikan semua pesanan yang sedang berjalan dulu.',
  'has_pending_payment': 'Masih ada pembayaran yang diproses. Coba lagi nanti.',
};

const _deleteAccountErrorMessages = {
  ..._refusalMessages,
  'unauthorized': 'Sesi kamu berakhir. Masuk lagi untuk menghapus akun.',
};

/// What the user must type before the delete button unlocks —
/// `CONFIRMATION_WORD` in `DeleteAccountSection.tsx`.
const deleteAccountConfirmationWord = 'HAPUS';

/// Mirrors `isDeleteAccountRefusal`: an expected refusal, not a failure worth
/// logging.
bool isDeleteAccountRefusal(String code) => _refusalMessages.containsKey(code);

/// Mirrors `translateDeleteAccountError`.
String translateDeleteAccountError(String code) =>
    _deleteAccountErrorMessages[code] ?? 'Gagal menghapus akun. Coba lagi.';
