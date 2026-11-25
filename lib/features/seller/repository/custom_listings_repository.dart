import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/user_message.dart';
import '../../../core/providers/supabase_provider.dart';
import 'models/custom_listing_form.dart';

/// What [CustomListingsRepository.save] answers: the listing's slug and
/// whether it is now live, or why it was refused.
typedef CustomListingSaveResult = ({
  String? slug,
  bool published,
  String? error,
});

/// The seller's own custom listings: a title, photos and tagged cards in
/// place of one catalog card.
///
/// Web saves through `POST /api/seller/custom-listings`, a thin wrapper over
/// `save_custom_listing`. The RPC is granted to `authenticated` and checks
/// everything the route does — the photos included (`_is_owned_listing_photo`)
/// — so the app calls it directly, as the rest of Kelola Listing does.
class CustomListingsRepository {
  CustomListingsRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'listing-photos';

  /// Web's upload limit for a listing photo.
  static const _maxUploadBytes = 4500000;

  /// One listing as its owner edits it, or null when there is none to edit.
  Future<CustomListingFormValue?> fetchForEdit(String slug) async {
    try {
      final row = await _client.rpc(
        'get_custom_listing',
        params: {'p_slug': slug},
      );
      if (row is! Map<String, dynamic>) return null;
      // `get_custom_listing` shows a live listing to anyone; only its owner
      // may edit it.
      if (row['user_id'] != _client.auth.currentUser?.id) return null;
      return CustomListingFormValue.fromDetail(row);
    } on PostgrestException catch (e) {
      // A slug that is not a uuid: there is no such listing.
      if (e.code == '22P02') return null;
      rethrow;
    }
  }

  /// Saves [value] as a draft, or publishes it when [publish].
  Future<CustomListingSaveResult> save(
    CustomListingFormValue value, {
    required bool publish,
  }) async {
    try {
      final result = await _client.rpc(
        'save_custom_listing',
        params: value.toRpcParams(publish: publish),
      );
      final map = result is Map ? result : const {};
      final slug = map['slug'] as String?;
      if (map['ok'] != true || slug == null) {
        return (
          slug: null,
          published: false,
          error: customListingSaveError('${map['error'] ?? ''}'),
        );
      }
      return (slug: slug, published: map['status'] == 'open', error: null);
    } on PostgrestException catch (e) {
      return (slug: null, published: false, error: userFacingError(e));
    }
  }

  /// The seller's unpublished custom listings, newest edit first — web's
  /// `fetchOwnCustomDrafts`. Own rows under RLS, so read directly.
  Future<List<CustomDraftSummary>> fetchDrafts() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('listings')
        .select('slug, title, price, quantity, photo_urls, updated_at')
        .eq('user_id', userId)
        .eq('kind', 'custom')
        .eq('status', 'draft')
        .isFilter('deleted_at', null)
        .order('updated_at', ascending: false)
        .limit(100);
    return [for (final row in rows) CustomDraftSummary.fromRow(row)];
  }

  /// Puts a photo in the seller's own `listing-photos/{uid}/` folder and
  /// returns its public URL — the only kind `save_custom_listing` takes.
  ///
  /// The file name is letters, digits and dots only, as the RPC's check
  /// (`_is_owned_listing_photo`) requires.
  Future<({String? url, String? error})> uploadPhoto(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return (url: null, error: 'Sesi berakhir.');
    if (bytes.lengthInBytes > _maxUploadBytes) {
      return (url: null, error: 'File terlalu besar (maks 4.5MB)');
    }
    final bucket = _client.storage.from(_bucket);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}'
        '${Random().nextInt(1 << 20).toRadixString(36)}.jpg';
    final path = '$userId/$name';
    try {
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
      return (url: bucket.getPublicUrl(path), error: null);
    } on StorageException catch (e) {
      return (url: null, error: userFacingError(e));
    }
  }

  /// Web's "Putar 90°": [url] turned a quarter clockwise, as a new upload.
  /// The original stays where it is until the listing is saved without it.
  Future<({String? url, String? error})> rotatePhoto(String url) async {
    final path = _pathOf(url);
    if (path == null) return (url: null, error: 'Foto tidak bisa diputar.');
    try {
      final original = await _client.storage.from(_bucket).download(path);
      final rotated = await compute(_rotateQuarter, original);
      if (rotated == null) {
        return (url: null, error: 'Gagal memutar foto. Coba lagi.');
      }
      return uploadPhoto(rotated);
    } on StorageException catch (e) {
      return (url: null, error: userFacingError(e));
    }
  }

  /// The object path inside the bucket of one of its public URLs.
  static String? _pathOf(String url) {
    const marker = '/storage/v1/object/public/$_bucket/';
    final at = url.indexOf(marker);
    if (at < 0) return null;
    return Uri.decodeComponent(url.substring(at + marker.length));
  }
}

/// Off the UI isolate: decoding and re-encoding a phone photo takes long
/// enough to drop frames.
Uint8List? _rotateQuarter(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return img.encodeJpg(img.copyRotate(decoded, angle: 90), quality: 90);
}

final customListingsRepositoryProvider = Provider(
  (ref) => CustomListingsRepository(ref.read(supabaseClientProvider)),
);
