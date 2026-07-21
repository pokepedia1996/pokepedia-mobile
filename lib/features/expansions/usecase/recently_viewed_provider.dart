import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the most-recently-viewed pack slugs for the current app session
/// (in-memory only — no persistence across restarts for this pass). Home's
/// "recently viewed" section watches this to know which packs to resolve.
class RecentlyViewedSlugsNotifier extends Notifier<List<String>> {
  static const _maxEntries = 10;

  @override
  List<String> build() => const [];

  void markViewed(String slug) {
    if (state.isNotEmpty && state.first == slug) return;
    final next = [slug, ...state.where((s) => s != slug)];
    state = next.take(_maxEntries).toList();
  }
}

final recentlyViewedSlugsProvider =
    NotifierProvider<RecentlyViewedSlugsNotifier, List<String>>(
      RecentlyViewedSlugsNotifier.new,
    );
