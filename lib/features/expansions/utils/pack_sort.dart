import '../../../shared/models/pack_model.dart';

/// Ports `PACK_SORT_OPTIONS` from `lib/utils/constants.ts`.
enum PackSortOption { newest, oldest, nameAsc, nameDesc }

extension PackSortOptionX on PackSortOption {
  String get labelId {
    switch (this) {
      case PackSortOption.newest:
        return 'Terbaru';
      case PackSortOption.oldest:
        return 'Terlama';
      case PackSortOption.nameAsc:
        return 'Nama A-Z';
      case PackSortOption.nameDesc:
        return 'Nama Z-A';
    }
  }

  /// Only the date sorts keep the series grouping — sorting by name flattens
  /// the list, exactly as `isGrouped` decides on the web.
  bool get isGrouped =>
      this == PackSortOption.newest || this == PackSortOption.oldest;
}

/// Ports `sortPacks` from `features/expansions/utils/sort.ts`, including its
/// `sortOrder` tie-break for sets sharing a release date.
List<PackModel> sortPacks(List<PackModel> packs, PackSortOption sortBy) {
  final sorted = [...packs];
  sorted.sort((a, b) {
    switch (sortBy) {
      case PackSortOption.oldest:
        final d = _releaseDate(a).compareTo(_releaseDate(b));
        return d != 0 ? d : a.sortOrder.compareTo(b.sortOrder);
      case PackSortOption.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case PackSortOption.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case PackSortOption.newest:
        final d = _releaseDate(b).compareTo(_releaseDate(a));
        return d != 0 ? d : b.sortOrder.compareTo(a.sortOrder);
    }
  });
  return sorted;
}

/// Unparseable dates sort last rather than throwing.
DateTime _releaseDate(PackModel pack) =>
    DateTime.tryParse(pack.releaseDate) ?? DateTime(1970);
