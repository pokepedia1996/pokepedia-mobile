import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';

/// Reads the minimum app version through Supabase rather than a pokepedia.id
/// route: it has to work signed out, and the edge firewall can challenge a
/// signed-out app.
class AppUpdateRepository {
  AppUpdateRepository(this._client);

  final SupabaseClient _client;

  /// The raw `min_app_version` row, or null without one.
  Future<String?> fetchMinVersion() async {
    final result = await _client.rpc('app_min_version');
    return result is String ? result : null;
  }
}

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository(ref.watch(supabaseClientProvider));
});
