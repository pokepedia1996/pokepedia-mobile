import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';

/// One booked banner. Mirrors `features/ads/schemas/ad-row.ts`.
class AdModel {
  const AdModel({
    required this.id,
    required this.companyName,
    required this.imageUrl,
    required this.href,
    required this.slotPosition,
  });

  final int id;
  final String companyName;

  /// Through the CDN proxy, as web's `mapAdRow` does.
  final String imageUrl;

  /// Where tapping goes — an external site for most bookings, an in-app
  /// path for a feature announcement.
  final String href;

  final int slotPosition;

  static AdModel? fromRow(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt();
    final image = proxyImageUrl(row['image_url'] as String?);
    // Nothing to draw is nothing to show: a row without artwork is a
    // booking that isn't ready, not a blank banner.
    if (id == null || image == null || image.isEmpty) return null;
    return AdModel(
      id: id,
      companyName: row['company_name'] as String? ?? '',
      imageUrl: image,
      href: row['href'] as String? ?? '',
      slotPosition: (row['slot_position'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ports `fetchAdsByPlacement` — what is booked for one slot right now.
///
/// Same filters as the web client, so both show the same campaign on the
/// same day: active, started, and either open-ended or not yet finished.
class AdsRepository {
  AdsRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      'id, company_name, image_url, href, slot_position, ad_type, '
      'page_placement';

  Future<List<AdModel>> fetchByPlacement(String placement) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final rows =
          await _client
                  .from('ads')
                  .select(_columns)
                  .eq('page_placement', placement)
                  .eq('is_active', true)
                  .lte('start_date', now)
                  .or('end_date.is.null,end_date.gte.$now')
                  .order('slot_position', ascending: true)
              as List;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          if (AdModel.fromRow(row) case final ad?) ad,
      ];
    } catch (_) {
      // An ad that fails to load is not worth an error on the page it sits
      // on — the slot simply isn't drawn.
      return const [];
    }
  }
}
