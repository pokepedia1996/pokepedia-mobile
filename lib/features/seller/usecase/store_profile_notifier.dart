import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/models/store_profile.dart';
import '../repository/store_profile_repository.dart';

/// The seller's own store settings row.
final storeProfileProvider = FutureProvider<StoreProfile?>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(null);
  return ref.read(storeProfileRepositoryProvider).fetch();
});
