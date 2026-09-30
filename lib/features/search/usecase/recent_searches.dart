import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The queries this device has searched, newest first.
///
/// Kept because the same card gets looked up repeatedly — a set number, a
/// print someone is hunting across several sellers — and retyping "pikachu
/// 130" every time is work the field can do instead.
///
/// Device-local rather than on the account: it is a typing shortcut, not
/// history worth syncing, and a shared phone should not hand one person's
/// searches to the next.
class RecentSearches extends Notifier<List<String>> {
  static const _key = 'recent_searches';

  /// Enough to cover "the thing I was just looking at" without the list
  /// becoming something to read rather than glance at.
  static const maxEntries = 8;

  SharedPreferences? _prefs;

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = _prefs?.getStringList(_key) ?? const [];
  }

  /// Records [query], moving it to the front if it is already there.
  ///
  /// Moved rather than duplicated: searching the same thing twice says it
  /// matters more, not that it deserves two rows.
  Future<void> record(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();
    final next = [
      trimmed,
      for (final entry in state)
        if (entry.toLowerCase() != lower) entry,
    ];
    state = next.take(maxEntries).toList();
    await _persist();
  }

  Future<void> remove(String query) async {
    state = [
      for (final entry in state)
        if (entry != query) entry,
    ];
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(
  RecentSearches.new,
);
