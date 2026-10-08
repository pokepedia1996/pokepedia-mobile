/// Turns anything thrown into a sentence a seller or buyer can act on.
///
/// Nothing the backend says is fit to show. Every `RAISE EXCEPTION` in the
/// schema raises a machine token — `card_not_found`, `trading_disabled`,
/// `coupon_expired` — and PostgREST's own failures are worse: "new row
/// violates row-level security policy for table \"listings\"" names a table
/// and a policy to someone trying to sell a card. Both used to reach the
/// screen verbatim through `catch (e) { return userFacingError(e); }`.
///
/// So the rule here is the opposite of the usual one: a message is shown
/// only if this file recognises it. Anything unrecognised becomes
/// [_generic], and the real text goes to the log instead, where it is
/// useful and harmless.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/card_condition.dart';
import '../network/pokepedia_api.dart';

/// What the reader sees when nothing more specific is known.
const _generic = 'Terjadi kesalahan. Coba lagi ya.';

/// The tokens the schema raises, in the words a person would use.
///
/// Only the ones a normal user can actually provoke are here. An admin-only
/// guard or a collision-exhausted retry loop is a bug or an attack, not
/// something to explain — those fall through to [_generic].
const _tokens = <String, String>{
  'not_authenticated': 'Sesi kamu berakhir. Masuk lagi ya.',
  'unauthenticated': 'Sesi kamu berakhir. Masuk lagi ya.',
  'unauthorized': 'Kamu tidak punya akses untuk melakukan ini.',
  'forbidden': 'Kamu tidak punya akses untuk melakukan ini.',
  'admin_only': 'Kamu tidak punya akses untuk melakukan ini.',
  'unavailable': 'Layanan sedang tidak tersedia. Coba lagi sebentar lagi.',
  'trading_disabled': 'Transaksi sedang dinonaktifkan sementara.',
  'not_found': 'Data yang kamu cari tidak ditemukan.',
  'card_not_found': 'Kartu ini tidak ditemukan.',
  'match_not_found': 'Pesanan ini tidak ditemukan.',
  'order_not_found': 'Pesanan ini tidak ditemukan.',
  'shipment_not_found': 'Pengiriman ini tidak ditemukan.',
  'deal_unavailable': 'Penawaran ini sudah tidak tersedia.',
  'photo_required': gradedPhotoRequiredMessage,
  'insufficient_stock': 'Stok tidak mencukupi.',
  'insufficient_balance': 'Saldo kamu tidak mencukupi.',
  'coupon_not_found': 'Kode kupon tidak ditemukan.',
  'coupon_expired': 'Kupon ini sudah kedaluwarsa.',
  'coupon_paused': 'Kupon ini sedang tidak aktif.',
  'coupon_not_applicable': 'Kupon ini tidak berlaku untuk pesanan ini.',
  'coupon_min_purchase': 'Belanjaanmu belum memenuhi minimum kupon ini.',
  'coupon_usage_limit_reached': 'Kuota kupon ini sudah habis.',
  'coupon_per_user_limit': 'Kamu sudah memakai kupon ini.',
  'invalid_account_number': 'Nomor rekening tidak valid.',
  'invalid_holder_name': 'Nama pemilik rekening tidak valid.',
  'invalid_bank_code': 'Bank yang dipilih tidak valid.',
  'invalid_status': 'Status ini tidak bisa diubah dari sini.',
  'destination_limit_exceeded': 'Jumlah rekening tersimpan sudah maksimal.',
  'delta_out_of_range': 'Jumlahnya di luar batas yang diizinkan.',
  'listing_reserved_by_deal':
      'Listing ini sedang dipakai di checkout pembeli. Tunggu sampai '
      'pembayarannya selesai.',
  'already_proposed':
      'Kamu sudah mengirim proposal ke semua pembeli di harga ini. Cek di '
      'halaman Proposal.',
  'no_open_bids': 'Tidak ada bid aktif di harga ini untuk dikirimi proposal.',
};

/// SQLSTATEs worth a sentence of their own. Everything else is [_generic].
const _sqlStates = <String, String>{
  '23505': 'Data ini sudah ada.',
  '23503': 'Data ini masih dipakai di tempat lain.',
  '42501': 'Kamu tidak punya akses untuk melakukan ini.',
  'PGRST301': 'Sesi kamu berakhir. Masuk lagi ya.',
};

/// The message to show for [error].
///
/// [fallback] replaces [_generic] where the caller knows the context — "Gagal
/// memuat listing" says more than "terjadi kesalahan" on a screen that was
/// trying to load listings.
String userFacingError(Object? error, {String? fallback}) {
  final generic = fallback ?? _generic;
  if (error == null) return generic;

  // Kept out of the UI but not lost: this is the line that says which table
  // or policy actually refused, and it is the only place it is any use.
  if (kDebugMode) debugPrint('[error] $error');

  if (error is SocketException || error is HandshakeException) {
    return 'Tidak bisa terhubung. Cek koneksi internetmu.';
  }
  if (error is TimeoutException) {
    return 'Server lama merespons. Coba lagi ya.';
  }
  if (error is AuthException) {
    return _authMessage(error) ?? generic;
  }
  if (error is PostgrestException) {
    return _postgrestMessage(error) ?? generic;
  }
  if (error is ApiException) {
    return _apiMessage(error) ?? generic;
  }
  if (error is String) {
    return _tokens[error] ?? generic;
  }
  return generic;
}

String? _postgrestMessage(PostgrestException error) {
  final byState = _sqlStates[error.code];
  if (byState != null) return byState;

  // `RAISE EXCEPTION 'token'` arrives as the bare token, sometimes with a
  // detail appended by `%` formatting — match the leading word.
  final token = error.message.trim().split(RegExp(r'[\s:,]')).first;
  return _tokens[token];
}

/// pokepedia.id routes already answer in Indonesian — the wallet withdraw,
/// dispatch, cancel and OTP routes all put the sentence in the body — so
/// that sentence is shown as is. Only a bare code is looked up instead.
String? _apiMessage(ApiException error) {
  final message = error.message;
  if (message != ApiException.genericMessage && !isErrorCode(message)) {
    return message;
  }
  return _tokens[error.code] ?? _tokens[message];
}

String? _authMessage(AuthException error) {
  final text = error.message.toLowerCase();
  if (text.contains('invalid login') || text.contains('invalid credentials')) {
    return 'Email atau kata sandi salah.';
  }
  if (text.contains('email not confirmed')) {
    return 'Emailmu belum dikonfirmasi. Cek kotak masukmu.';
  }
  if (text.contains('already registered')) {
    return 'Email ini sudah terdaftar.';
  }
  if (text.contains('rate limit') || text.contains('too many')) {
    return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
  }
  return null;
}
