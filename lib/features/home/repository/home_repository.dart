import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/pack_model.dart';
import '../../expansions/repository/expansions_repository.dart';

/// Data access for the Home feature, backed by Supabase via
/// [ExpansionsRepository].
class HomeRepository {
  HomeRepository(this._client, this._expansionsRepository);

  final SupabaseClient _client;
  final ExpansionsRepository _expansionsRepository;

  Future<List<PackModel>> fetchExplorePacks({String language = 'id'}) {
    return _expansionsRepository.fetchPacks(language: language);
  }

  /// Resolves the given (most-recent-first) pack slugs against Supabase.
  /// Falls back to the first few explore packs when there's no view
  /// history yet (fresh app session).
  Future<List<PackModel>> fetchRecentlyViewed(
    List<String> slugs, {
    String language = 'id',
  }) async {
    if (slugs.isEmpty) {
      final explore = await fetchExplorePacks(language: language);
      return explore.take(6).toList();
    }

    final rows = await _client
        .from('expansions')
        .select(
          'code, name_id, pack_image_url, set_symbol_url, released_at, '
          'total_cards, sort_order, language, code_lower, '
          'series:series_id(name_id, series_image_url)',
        )
        .inFilter('code_lower', slugs)
        .eq('language', language);

    final bySlug = {
      for (final r in rows) r['code_lower'] as String: PackModel.fromRow(r),
    };
    return slugs.map((s) => bySlug[s]).whereType<PackModel>().toList();
  }
}
