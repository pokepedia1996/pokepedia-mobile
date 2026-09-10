import 'app_search_field.dart';
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
  const QuickSearchField({super.key, this.onScan});

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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_syncPanel);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _hasQuery => _query.length >= QuickSearchRepository.minQueryLength;

  void _syncPanel() {
    final show = _focus.hasFocus && _hasQuery;
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

  void _searchAll() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _dismiss();
    context.push(Routes.searchResults(query));
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
  });

  final LayerLink link;
  final double? width;
  final String query;
  final VoidCallback onDismiss;
  final ValueChanged<CardModel> onCard;
  final ValueChanged<StoreModel> onStore;
  final VoidCallback onSearchAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(quickSearchProvider(query));

    return Stack(
      children: [
        // Anything outside the panel closes it, the way a click outside the
        // dropdown does on web.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Material(
                color: Theme.of(context).cardColor,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: context.borderColor),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: async.when(
                          loading: () => const _PanelMessage(
                            child: LinearProgressIndicator(minHeight: 2),
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
    return ConstrainedBox(
      // Web's `max-h-[320px]`, so the panel never swallows the screen.
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView(
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
      ),
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
