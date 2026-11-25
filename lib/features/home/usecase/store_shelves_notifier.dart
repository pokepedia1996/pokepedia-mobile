import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/store_shelf.dart';
import 'home_notifier.dart';

/// What "Listing baru dari toko" has loaded so far.
class StoreShelvesState {
  const StoreShelvesState({
    this.shelves = const [],
    this.nextOffset = 0,
    this.hasMore = true,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<StoreShelf> shelves;
  final int nextOffset;
  final bool hasMore;
  final bool loadingMore;

  /// The last "more" failed. Scrolling doesn't retry it on every frame;
  /// the "Coba lagi" row or a pull-to-refresh does.
  final bool moreFailed;

  StoreShelvesState copyWith({
    List<StoreShelf>? shelves,
    int? nextOffset,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
  }) => StoreShelvesState(
    shelves: shelves ?? this.shelves,
    nextOffset: nextOffset ?? this.nextOffset,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// The store shelves at the foot of Beranda, a page of stores at a time:
/// the first with the page, the rest as the reader scrolls to the end.
class StoreShelvesNotifier extends AsyncNotifier<StoreShelvesState> {
  @override
  Future<StoreShelvesState> build() async {
    final page = await ref.read(homeRepositoryProvider).fetchStoreShelves();
    return StoreShelvesState(
      shelves: page.shelves,
      nextOffset: page.nextOffset,
      hasMore: page.hasMore,
    );
  }

  /// The next page, unless one is loading, the last failed ([retry] clears
  /// that), or there is none.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.moreFailed) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(homeRepositoryProvider)
          .fetchStoreShelves(offset: current.nextOffset);
      state = AsyncData(
        current.copyWith(
          shelves: [...current.shelves, ...page.shelves],
          nextOffset: page.nextOffset,
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  Future<void> retry() async {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(current.copyWith(moreFailed: false));
    await loadMore();
  }
}

final storeShelvesProvider =
    AsyncNotifierProvider<StoreShelvesNotifier, StoreShelvesState>(
      StoreShelvesNotifier.new,
    );
