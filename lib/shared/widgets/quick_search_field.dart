import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../features/search/usecase/quick_search_notifier.dart';
import '../models/card_model.dart';
import '../models/store_model.dart';
import '../../features/search/usecase/recent_searches.dart';
import 'app_search_field.dart';
import 'card_art.dart';
import 'seller_avatar.dart';

/// The top bar's search field: type and the matches come to you.
///
/// Ports the navbar's `ExpandableSearchBar` + `SearchSuggestionsDropdown` —
/// stores first, then cards, then a row that hands the whole query to
/// advanced search. Tapping the field used to jump straight to that form,
/// which made the commonest search — "where is this card" — the long way
/// round.
class QuickSearchField extends ConsumerStatefulWidget {
  /// The dropdown card itself — absent entirely when there is nothing to
  /// put in it, which is what tests assert on.
  static const panelKey = ValueKey('quick-search-panel');

  const QuickSearchField({super.key, this.onScan, this.initialQuery});

  /// What the field starts with — the query a results page was opened for.
  ///
  /// Prefilled rather than run: arriving on results for "pikachu 130" and
  /// wanting "pikachu 131" should be one keystroke, not a retype.
  final String? initialQuery;

  /// Opens the scanner from the camera inside the field. See
  /// [AppSearchField.onScan].
  final VoidCallback? onScan;

  /// Web debounces every keystroke by this much before asking the server.
  static const _debounce = Duration(milliseconds: 300);

  @override
  ConsumerState<QuickSearchField> createState() => _QuickSearchFieldState();
}

class _QuickSearchFieldState extends ConsumerState<QuickSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _panel = OverlayPortalController();

  Timer? _debounce;

  /// The query the suggestions are for — the typed text, one debounce behind.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_syncPanel);
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      // Set here too, so focusing the prefilled field answers straight away
      // instead of waiting for a keystroke it may never get.
      _query = initial;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_syncPanel);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncPanel() {
    // Focused is enough. Below the minimum query the panel still has
    // something to say — the searches this device has run before, which is
    // the whole point of showing it the moment the field is tapped.
    final show = _focus.hasFocus;
    if (show == _panel.isShowing) return;
    show ? _panel.show() : _panel.hide();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final typed = value.trim();
    // Below the minimum there is nothing to ask for, so the panel closes now
    // rather than after the debounce.
    if (typed.length < QuickSearchRepository.minQueryLength) {
      setState(() => _query = typed);
      _syncPanel();
      return;
    }
    _debounce = Timer(QuickSearchField._debounce, () {
      if (!mounted) return;
      setState(() => _query = typed);
      _syncPanel();
    });
  }

  void _dismiss() {
    _focus.unfocus();
    _panel.hide();
  }

  /// Leaves the text in place: coming back from a card to refine the same
  /// search is the common next step.
  void _open(String route) {
    _dismiss();
    context.push(route);
  }

  void _searchAll() => _run(_controller.text, Routes.searchResults);

  /// Runs [query] through [route], recording it as a recent search first.
  ///
  /// Recorded here rather than on the results page: this is the point where
  /// someone has decided what they are looking for, and the scopes below all
  /// pass through it.
  void _run(String query, String Function(String) route) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).record(trimmed);
    _dismiss();

    final target = route(trimmed);
    // Searching again from a results page replaces it rather than stacking:
    // otherwise four refinements of the same query leave four near-identical
    // pages to back out through to reach whatever came before them.
    if (GoRouterState.of(context).uri.path == Uri.parse(target).path) {
      context.pushReplacement(target);
    } else {
      context.push(target);
    }
  }

  /// Puts a recent search back in the field rather than running it — the
  /// common next step after "pikachu 130" is "pikachu 131".
  void _useRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    setState(() => _query = query);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _panel,
      overlayChildBuilder: (overlayContext) => _SuggestionsOverlay(
        link: _link,
        width: _link.leaderSize?.width,
        query: _query,
        onDismiss: _dismiss,
        onCard: (card) => _open(Routes.cardDetail(card.packSlug, card.id)),
        onStore: (store) => _open(Routes.storeDetail(store.handle)),
        onSearchAll: _searchAll,
        onScope: _run,
        onRecent: _useRecent,
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: AppSearchField(
          hintText: 'Cari kartu...',
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          onSubmitted: (_) => _searchAll(),
          onScan: widget.onScan,
        ),
      ),
    );
  }
}

/// The dropdown itself, anchored under the field.
class _SuggestionsOverlay extends ConsumerWidget {
  const _SuggestionsOverlay({
    required this.link,
    required this.width,
    required this.query,
    required this.onDismiss,
    required this.onCard,
    required this.onStore,
    required this.onSearchAll,
    required this.onScope,
    required this.onRecent,
  });

  final LayerLink link;
  final double? width;
  final String query;
  final VoidCallback onDismiss;
  final ValueChanged<CardModel> onCard;
  final ValueChanged<StoreModel> onStore;
  final VoidCallback onSearchAll;

  /// Runs the typed query against one scope — Market, Katalog or stores.
  final void Function(String query, String Function(String) route) onScope;

  /// Puts a past search back in the field.
  final ValueChanged<String> onRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final hasQuery = query.length >= QuickSearchRepository.minQueryLength;
    final recents = ref.watch(recentSearchesProvider);

    // Anything outside the panel closes it, the way a click outside the
    // dropdown does on web. It stays even when the panel itself doesn't, so
    // a tap elsewhere still dismisses the focused field.
    final barrier = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: const SizedBox.expand(),
      ),
    );

    // An empty field with no history has nothing to put in the panel, and a
    // card holding one line of grey instruction just covers the page it was
    // opened over.
    if (!hasQuery && recents.isEmpty) {
      return Stack(children: [barrier]);
    }

    final async = ref.watch(quickSearchProvider(query));

    return Stack(
      children: [
        barrier,
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              key: QuickSearchField.panelKey,
              // The dropdown may grow with its content but never past two
              // thirds of the screen: past that it stops reading as a panel
              // over the page and starts reading as a new page.
              constraints: BoxConstraints(
                maxWidth: width ?? double.infinity,
                maxHeight: MediaQuery.sizeOf(context).height * 0.65,
              ),
              child: Material(
                color: Theme.of(context).cardColor,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    border: Border.all(color: context.borderColor),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nothing typed yet: the panel offers what this device
                      // has searched before instead of an empty box.
                      if (!hasQuery)
                        Flexible(child: _RecentSearches(onUse: onRecent))
                      else ...[
                        // Where to look, before what was found. The same
                        // three words mean different things in the
                        // marketplace, the catalog and the shop directory,
                        // and the reader knows which they meant.
                        _ScopeRows(query: query, onScope: onScope),
                        Divider(height: 1, color: context.borderColor),
                        Flexible(
                          child: async.when(
                            // A bar pinned to the top edge of the results
                            // area read as part of the panel's chrome; a
                            // spinner sits where the rows will be, so the
                            // wait happens in the place being waited on.
                            loading: () => _PanelMessage(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.mutedForeground,
                                ),
                              ),
                            ),
                            error: (_, __) => _PanelMessage(
                              child: Text(
                                'Pencarian gagal. Coba lagi.',
                                style: AppTypography.caption(colors.error),
                              ),
                            ),
                            data: (results) => results.isEmpty
                                ? _PanelMessage(
                                    child: Text(
                                      'Tidak ada hasil untuk "$query"',
                                      style: AppTypography.caption(
                                        context.mutedForeground,
                                      ),
                                    ),
                                  )
                                : _Results(
                                    results: results,
                                    onCard: onCard,
                                    onStore: onStore,
                                  ),
                          ),
                        ),
                      ],
                      if (hasQuery) ...[
                        Divider(height: 1, color: context.borderColor),
                        InkWell(
                          onTap: onSearchAll,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    "Cari semua untuk '$query'",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.captionSemibold(
                                      context.mutedForeground,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  LucideIcons.arrowRight,
                                  size: 12,
                                  color: context.mutedForeground,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.onCard,
    required this.onStore,
  });

  final QuickSearchResults results;
  final ValueChanged<CardModel> onCard;
  final ValueChanged<StoreModel> onStore;

  @override
  Widget build(BuildContext context) {
    // Unbounded on purpose: the panel's own 65% cap is what stops this
    // growing, and a second limit here would fight it on a tall screen.
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        if (results.stores.isNotEmpty) ...[
          const _SectionLabel('Toko'),
          for (final store in results.stores)
            _StoreRow(store: store, onTap: () => onStore(store)),
          if (results.cards.isNotEmpty)
            Divider(
              height: 9,
              indent: 10,
              endIndent: 10,
              color: context.borderColor.withValues(alpha: 0.6),
            ),
        ],
        if (results.cards.isNotEmpty) ...[
          const _SectionLabel('Kartu'),
          for (final card in results.cards)
            _CardRow(card: card, onTap: () => onCard(card)),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Text(
        label,
        style: AppTypography.caption(
          context.mutedForeground.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final CardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 32, child: CardArt(imageUrl: card.imageUrl)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    card.collectorNumber,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            SellerAvatar(
              name: store.storeName,
              imageUrl: store.logoUrl,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          store.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                      ),
                      if (store.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.badgeCheck,
                          size: 13,
                          color: colors.primary,
                        ),
                      ],
                    ],
                  ),
                  if (store.cityName.isNotEmpty)
                    Text(
                      store.cityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Center(child: child),
    );
  }
}

/// Where to look — the three scopes web offers above its card results.
///
/// The same words mean different things in each: "pika" in Market is stock
/// someone is selling right now, in Katalog it is every print ever made, and
/// as a shop name it is a seller. Guessing on the reader's behalf is how a
/// search for a shop returns four hundred cards.
class _ScopeRows extends StatelessWidget {
  const _ScopeRows({required this.query, required this.onScope});

  final String query;
  final void Function(String query, String Function(String) route) onScope;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ScopeRow(
          icon: LucideIcons.shoppingBag,
          label: 'Cari',
          query: query,
          suffix: 'di Market',
          onTap: () => onScope(query, Routes.marketSearch),
        ),
        _ScopeRow(
          icon: LucideIcons.layoutGrid,
          label: 'Cari',
          query: query,
          suffix: 'di Katalog',
          onTap: () => onScope(query, Routes.searchResults),
        ),
        _ScopeRow(
          icon: LucideIcons.store,
          label: 'Cari toko',
          query: query,
          onTap: () => onScope(query, Routes.marketStoreSearch),
        ),
      ],
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.icon,
    required this.label,
    required this.query,
    required this.onTap,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String query;
  final String? suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.mutedForeground.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 16, color: colors.onSurface),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$label '),
                    // The query quoted and bolded, so the row reads as an
                    // instruction about what was typed rather than a label.
                    TextSpan(
                      text: '"$query"',
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    if (suffix != null) TextSpan(text: ' $suffix'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(colors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What this device has searched before, newest first.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onUse});

  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    // The overlay hides itself rather than render this empty, so reaching
    // here with nothing means the list emptied under us mid-frame.
    if (recents.isEmpty) return const SizedBox.shrink();

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pencarian terakhir',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: AppTypography.caption(context.mutedForeground),
                ),
                child: const Text('Hapus semua'),
              ),
            ],
          ),
        ),
        for (final entry in recents)
          InkWell(
            onTap: () => onUse(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.history,
                    size: 16,
                    color: context.mutedForeground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm(context.appColors.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14),
                    color: context.mutedForeground,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Hapus "$entry"',
                    onPressed: () =>
                        ref.read(recentSearchesProvider.notifier).remove(entry),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
