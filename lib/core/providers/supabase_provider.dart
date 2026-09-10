import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single Supabase client instance, exposed as a provider so
/// repositories follow the same `Provider((ref) => XRepository(...))`
/// dependency-injection convention used across the app instead of reaching
/// for `Supabase.instance.client` directly.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
