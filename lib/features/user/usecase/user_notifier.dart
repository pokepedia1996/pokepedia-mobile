import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_model.dart';
import '../repository/user_repository.dart';

final userRepositoryProvider = Provider((ref) {
  return UserRepository(ref.read(supabaseClientProvider));
});

final usersSearchQueryProvider = StateProvider<String>((ref) => '');

final usersSearchProvider = FutureProvider<List<UserModel>>((ref) {
  final query = ref.watch(usersSearchQueryProvider);
  return ref.read(userRepositoryProvider).search(query);
});

final userProfileProvider = FutureProvider.family<UserModel?, String>((
  ref,
  username,
) {
  return ref.read(userRepositoryProvider).fetchByUsername(username);
});
