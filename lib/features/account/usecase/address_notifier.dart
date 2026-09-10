import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/address_repository.dart';
import '../repository/models/address_model.dart';

final addressRepositoryProvider = Provider((ref) {
  return AddressRepository(ref.read(supabaseClientProvider));
});

/// The signed-in user's saved delivery addresses, primary first.
final addressesProvider = FutureProvider<List<AddressModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(addressRepositoryProvider).fetchAddresses();
});

/// The bundled province/regency/district dataset behind the address form.
final areaCatalogProvider = FutureProvider<AreaCatalog>((ref) {
  return AreaCatalog.load();
});
