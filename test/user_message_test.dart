import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/errors/user_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nothing the backend says is fit to show. Every `RAISE EXCEPTION` in the
/// schema raises a machine token, and PostgREST's own failures name tables
/// and policies — both used to reach the screen verbatim.
void main() {
  group('what must never reach the screen', () {
    test('an RLS refusal does not name the table or the policy', () {
      final message = userFacingError(
        const PostgrestException(
          message:
              'new row violates row-level security policy for table "listings"',
          code: '42501',
        ),
      );

      expect(message, isNot(contains('listings')));
      expect(message, isNot(contains('policy')));
      expect(message, isNot(contains('row-level')));
    });

    test('a missing table is not described to the reader', () {
      final message = userFacingError(
        const PostgrestException(
          message: 'relation "public.collection_value_snapshots" does not exist',
          code: '42P01',
        ),
      );

      expect(message, isNot(contains('relation')));
      expect(message, isNot(contains('collection_value_snapshots')));
      expect(message, 'Terjadi kesalahan. Coba lagi ya.');
    });

    test('a SQLSTATE never appears', () {
      for (final code in ['42501', '23505', '42P01', 'PGRST116']) {
        expect(
          userFacingError(PostgrestException(message: 'boom', code: code)),
          isNot(contains(code)),
          reason: code,
        );
      }
    });

    test('an unknown token is not shown raw', () {
      final message = userFacingError(
        const PostgrestException(message: 'escrow_release_buyer_mismatch'),
      );
      expect(message, isNot(contains('escrow')));
    });
  });

  group('what is worth saying', () {
    test('the tokens a user can actually provoke get a sentence', () {
      expect(
        userFacingError(const PostgrestException(message: 'card_not_found')),
        'Kartu ini tidak ditemukan.',
      );
      expect(
        userFacingError(const PostgrestException(message: 'coupon_expired')),
        'Kupon ini sudah kedaluwarsa.',
      );
      // `RAISE EXCEPTION 'order_not_found_for_shipment_%'` arrives with the
      // id appended; the leading token is what identifies it.
      expect(
        userFacingError(
          const PostgrestException(message: 'not_found: 91823'),
        ),
        'Data yang kamu cari tidak ditemukan.',
      );
    });

    test('a duplicate is named by its SQLSTATE, not its constraint', () {
      final message = userFacingError(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint "listings_slug_key"',
          code: '23505',
        ),
      );
      expect(message, 'Data ini sudah ada.');
      expect(message, isNot(contains('listings_slug_key')));
    });

    test('losing the network says so, rather than "coba lagi"', () {
      expect(
        userFacingError(const SocketException('failed host lookup')),
        contains('koneksi'),
      );
      expect(
        userFacingError(TimeoutException('too slow')),
        contains('lama merespons'),
      );
    });

    test('a bad password is a sentence, not a provider string', () {
      expect(
        userFacingError(const AuthException('Invalid login credentials')),
        'Email atau kata sandi salah.',
      );
    });

    test('the caller can say what was being done', () {
      expect(
        userFacingError(
          const PostgrestException(message: 'something internal'),
          fallback: 'Gagal memuat listing.',
        ),
        'Gagal memuat listing.',
      );
    });

    test('null is not an error worth a scary message', () {
      expect(userFacingError(null), 'Terjadi kesalahan. Coba lagi ya.');
    });
  });
}
