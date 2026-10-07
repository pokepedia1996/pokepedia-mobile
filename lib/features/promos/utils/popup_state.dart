/// Per-campaign frequency record — web's `PopupSlugState` in
/// `features/promos/schemas/promo-popup.ts`. Times are epoch milliseconds.
class PopupSlugState {
  const PopupSlugState({
    this.shownCount = 0,
    this.dismissCount = 0,
    this.lastShownAt = 0,
    this.snoozedUntil = 0,
    this.clickedAt,
  });

  /// Web's `PopupSlugStateSchema`: null for anything that isn't a
  /// non-negative integer where one is required.
  static PopupSlugState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? count(Object? value) => value is int && value >= 0 ? value : null;
    final shownCount = count(raw['shownCount']);
    final dismissCount = count(raw['dismissCount']);
    final lastShownAt = count(raw['lastShownAt']);
    final snoozedUntil = count(raw['snoozedUntil']);
    if (shownCount == null ||
        dismissCount == null ||
        lastShownAt == null ||
        snoozedUntil == null) {
      return null;
    }
    final rawClicked = raw['clickedAt'];
    final clickedAt = count(rawClicked);
    if (rawClicked != null && clickedAt == null) return null;
    return PopupSlugState(
      shownCount: shownCount,
      dismissCount: dismissCount,
      lastShownAt: lastShownAt,
      snoozedUntil: snoozedUntil,
      clickedAt: clickedAt,
    );
  }

  final int shownCount;
  final int dismissCount;
  final int lastShownAt;
  final int snoozedUntil;
  final int? clickedAt;

  PopupSlugState copyWith({
    int? shownCount,
    int? dismissCount,
    int? lastShownAt,
    int? snoozedUntil,
    int? clickedAt,
  }) => PopupSlugState(
    shownCount: shownCount ?? this.shownCount,
    dismissCount: dismissCount ?? this.dismissCount,
    lastShownAt: lastShownAt ?? this.lastShownAt,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    clickedAt: clickedAt ?? this.clickedAt,
  );

  Map<String, Object> toJson() => {
    'shownCount': shownCount,
    'dismissCount': dismissCount,
    'lastShownAt': lastShownAt,
    'snoozedUntil': snoozedUntil,
    if (clickedAt != null) 'clickedAt': clickedAt!,
  };
}

/// Keyed by campaign slug — web's `PopupState`.
typedef PopupState = Map<String, PopupSlugState>;

/// Entries outlive a paused campaign, so reactivating one does not resurrect
/// the popup — web's `ENTRY_RETENTION_MS`.
const popupEntryRetentionMs = 180 * 24 * 60 * 60 * 1000;

const _hourMs = 60 * 60 * 1000;

/// Web's `readPopupState` parse: an unreadable blob is an empty state, the
/// same as a device that has never seen a popup.
PopupState parsePopupState(Object? raw) {
  if (raw is! Map) return {};
  final state = <String, PopupSlugState>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final parsed = PopupSlugState.fromJson(entry.value);
    // Web's `z.record` rejects the whole blob on one bad entry.
    if (key is! String || parsed == null) return {};
    state[key] = parsed;
  }
  return state;
}

Map<String, Object> encodePopupState(PopupState state) => {
  for (final entry in state.entries) entry.key: entry.value.toJson(),
};

int _touchedAt(PopupSlugState entry) {
  final clickedAt = entry.clickedAt ?? 0;
  return entry.lastShownAt > clickedAt ? entry.lastShownAt : clickedAt;
}

/// The pruning half of web's `writePopupState`.
PopupState prunePopupState(PopupState state, int now) => {
  for (final entry in state.entries)
    if (now - _touchedAt(entry.value) < popupEntryRetentionMs)
      entry.key: entry.value,
};

PopupSlugState _entry(PopupState state, String slug) =>
    state[slug] ?? const PopupSlugState();

/// Web's `recordShown`: counts the impression and snoozes the campaign for
/// its cooldown.
PopupState withShown(
  PopupState state,
  String slug,
  int cooldownHours,
  int now,
) {
  final entry = _entry(state, slug);
  return prunePopupState({
    ...state,
    slug: entry.copyWith(
      shownCount: entry.shownCount + 1,
      lastShownAt: now,
      snoozedUntil: now + cooldownHours * _hourMs,
    ),
  }, now);
}

/// Web's `recordDismissed`.
PopupState withDismissed(PopupState state, String slug, int now) {
  final entry = _entry(state, slug);
  return prunePopupState({
    ...state,
    slug: entry.copyWith(dismissCount: entry.dismissCount + 1),
  }, now);
}

/// Web's `recordClicked`: a campaign the user acted on never shows again.
PopupState withClicked(PopupState state, String slug, int now) {
  final entry = _entry(state, slug);
  return prunePopupState({...state, slug: entry.copyWith(clickedAt: now)}, now);
}
