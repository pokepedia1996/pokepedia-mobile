import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_pagination.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/proposal_card_group.dart';
import '../repository/models/sent_proposal.dart';
import '../usecase/proposals_notifier.dart';

/// Ports `app/proposals/page.tsx` — negotiated offers on ask listings
/// (`listing_offers`) and bid-fulfillment proposals sellers send for the
/// buyer's WTB bids (`bid_proposals`).
class ProposalsPage extends ConsumerStatefulWidget {
  const ProposalsPage({super.key, this.initialFilter = ProposalFeedFilter.all});

  /// Which status chip to preselect. The market banner uses this to land on
  /// whatever its subtitle just described.
  final ProposalFeedFilter initialFilter;

  @override
  ConsumerState<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends ConsumerState<ProposalsPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: setting provider state during build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(proposalFeedFilterProvider.notifier).state =
          widget.initialFilter;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(),
      body: const AppBarOverlayBody(child: _CardFeedTab()),
    );
  }
}

/// "Proposal Saya" and what the page holds. Part of the feed's scroll, so
/// it moves away with the cards instead of holding a band of the screen.
class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proposal Saya',
            style: AppTypography.h1(context.appColors.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Aktivitas bid dan proposal kamu, dikelompokkan per kartu.',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Ports the filter group in `card-feed-list.tsx`: one muted track with the
/// options inside it, the active one raised onto the card colour.
///
/// A row of separate pills, which is what this was, makes each option look
/// like its own control — a set of things you might turn on. A track makes
/// them one control with one answer, which is what a filter is.
class _FilterTrack extends StatelessWidget {
  const _FilterTrack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        // Full width, like the block-level `div` web draws it as. The
        // options still start at the left inside it rather than being
        // stretched to fill — a filter whose widths move as the counts
        // change is harder to aim at than one that stays put.
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.appColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.md);

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          // `bg-card shadow-sm` for the one that's on; nothing at all for
          // the rest, so the track shows through.
          color: selected ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: radius,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: selected
              ? AppTypography.captionSemibold(colors.onSurface)
              : AppTypography.caption(context.mutedForeground),
        ),
      ),
    );
  }
}

/// Web's `PROPOSALS_PER_PAGE` and the sizes its selector offers here.
const _defaultPageSize = 15;
const _pageSizeOptions = [15, 25, 50, 100];

/// Ports `card-feed-list.tsx`, paged as web pages it: the whole feed is
/// loaded and grouped once, then shown a page at a time — the counts on the
/// filter are over every card, not just the page on screen.
/// Whether [group]'s card answers [query]: every word of it found in the
/// card's name, set code or collector number, ignoring case. "pikachu",
/// "sv8 pikachu" and "094" all find the same card; a leading `#` on a
/// number is dropped, as people write numbers both ways.
bool matchesProposalSearch(ProposalCardGroup group, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.startsWith('#') ? w.substring(1) : w)
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final card = group.card;
  final haystack = '${card.name} ${card.expansionCode} ${card.collectorNumber}'
      .toLowerCase();
  return words.every(haystack.contains);
}

class _CardFeedTab extends ConsumerStatefulWidget {
  const _CardFeedTab();

  @override
  ConsumerState<_CardFeedTab> createState() => _CardFeedTabState();
}

class _CardFeedTabState extends ConsumerState<_CardFeedTab> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  /// What the search box holds. The whole feed is already loaded, so it
  /// narrows on the device as the reader types, with no round trip.
  String _search = '';

  /// 1-based, like web's.
  int _page = 1;
  int _pageSize = _defaultPageSize;

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// The heading and count above the pinned filter — how far the list
  /// scrolls before the filter sticks.
  final _introKey = GlobalKey();

  void _goTo(int page) {
    setState(() => _page = page);
    // A new page starts at its first card, not wherever the last one was
    // left: scrolled just far enough that the filter is pinned over it.
    // Already above that point, the reader is looking at the top anyway.
    if (!_scroll.hasClients) return;
    final intro = _introKey.currentContext?.size?.height ?? 0;
    if (_scroll.offset > intro) _scroll.jumpTo(intro);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(proposalCardFeedProvider);
    final filter = ref.watch(proposalFeedFilterProvider);
    // A new filter or a reload starts from the first page, as web's
    // `setPage(1)` beside each does.
    ref.listen(proposalFeedFilterProvider, (_, __) => _goTo(1));
    // Only a reload: loading older activity keeps the reader where they are.
    ref.listen(proposalCardFeedProvider, (previous, next) {
      if ((previous?.isLoading ?? true) && next.hasValue && !next.isLoading) {
        _goTo(1);
      }
    });

    // The states with nothing to scroll keep the heading above them.
    Widget withHeading(Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading(),
        Expanded(child: child),
      ],
    );

    return async.when(
      loading: () => withHeading(const PikachuLoader()),
      error: (_, __) => withHeading(
        Center(
          child: Text(
            'Gagal memuat proposal',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      ),
      data: (feed) {
        final groups = feed.groups;
        if (groups.isEmpty) {
          return withHeading(
            const EmptyState(
              icon: LucideIcons.inbox,
              title: 'Belum ada aktivitas',
              description:
                  'Pasang bid (WTB) atau kirim proposal untuk mulai '
                  'bernegosiasi.',
            ),
          );
        }

        // The search narrows first, so the chip counts below are counts of
        // what it found — a chip saying 4 over a list of 1 would be wrong.
        final searched = _search.isEmpty
            ? groups
            : groups.where((g) => matchesProposalSearch(g, _search)).toList();
        final visible = searched.where(filter.matches).toList();
        final pageCount = (visible.length / _pageSize).ceil();
        // A page that no longer exists — the feed shrank under it — shows
        // the last one there is, as web's `safePage` does.
        final page = _page.clamp(1, pageCount < 1 ? 1 : pageCount);
        final shown = visible
            .skip((page - 1) * _pageSize)
            .take(_pageSize)
            .toList();

        return RefreshIndicator(
          onRefresh: () => ref.refresh(proposalCardFeedProvider.future),
          // One scroll for the whole page: the heading and the count go up
          // with the cards, and the filter pins to the top once they have,
          // so changing it never means scrolling back.
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  key: _introKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Heading(),
                    // Web states the size of the feed above the filter, so
                    // the count on "Semua" has something to be a share of.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        // "30+": the newest activity is loaded, older is not.
                        '${groups.length}${feed.hasMore ? '+' : ''} '
                        'kartu dengan aktivitas',
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                      child: AppSearchField(
                        hintText: 'Cari kartu, set, atau nomor',
                        controller: _searchController,
                        onChanged: (value) {
                          _search = value.trim();
                          _goTo(1);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedFilter(
                  textScaler: MediaQuery.textScalerOf(context),
                  child: _FilterTrack(
                    children: [
                      for (final option in ProposalFeedFilter.values)
                        // Web drops a chip with nothing behind it; "Semua"
                        // always stands so there is a way back.
                        if (option == ProposalFeedFilter.all ||
                            searched.any(option.matches))
                          _FilterChip(
                            label:
                                '${option.label} '
                                '(${searched.where(option.matches).length})',
                            selected: filter == option,
                            onTap: () =>
                                ref
                                        .read(
                                          proposalFeedFilterProvider.notifier,
                                        )
                                        .state =
                                    option,
                          ),
                    ],
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _search.isEmpty
                        ? const EmptyState(
                            icon: LucideIcons.filterX,
                            title: 'Tidak ada kartu untuk filter ini',
                          )
                        : EmptyState(
                            icon: LucideIcons.searchX,
                            title: 'Tidak ada kartu yang cocok',
                            description:
                                'Tidak ada "$_search" di proposal '
                                'kamu.',
                          ),
                  ),
                ),
              // Nothing among what is loaded, but older activity may hold it.
              if (visible.isEmpty && feed.hasMore)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  sliver: SliverToBoxAdapter(child: _LoadOlder(feed: feed)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverList.list(
                    children: [
                      for (final (i, group) in shown.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _CardGroupRow(group: group),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: AppPagination(
                          page: page,
                          pageCount: pageCount,
                          onPage: _goTo,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: PageSizeSelector(
                          value: _pageSize,
                          options: _pageSizeOptions,
                          onChanged: (size) {
                            _pageSize = size;
                            _goTo(1);
                          },
                        ),
                      ),
                      if (feed.hasMore) ...[
                        const SizedBox(height: 16),
                        _LoadOlder(feed: feed),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Holds the filter track at the top of the scroll once the heading has
/// gone. Drawn on the page's own background so cards passing beneath it
/// don't show through between the chips.
class _PinnedFilter extends SliverPersistentHeaderDelegate {
  const _PinnedFilter({required this.child, required this.textScaler});

  final Widget child;

  /// The reader's text size: a pinned header can't size itself to its
  /// content, so the height is worked out from the chip's line instead.
  final TextScaler textScaler;

  /// The track — two 7dp chip paddings and the 4dp inset each side around
  /// one caption line (12sp at 1.4) — with 8dp of air above and below.
  double get _extent => 22 + 16 + textScaler.scale(12 * 1.4);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedFilter oldDelegate) =>
      oldDelegate.child != child || oldDelegate.textScaler != textScaler;
}

/// "Muat aktivitas lebih lama": the next batch of bids and proposals. The
/// pages above only cover what has loaded, so this is the way past them.
class _LoadOlder extends ConsumerWidget {
  const _LoadOlder({required this.feed});

  final ProposalFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: feed.loadingMore
            ? null
            : () => ref.read(proposalCardFeedProvider.notifier).loadMore(),
        child: feed.loadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Muat aktivitas lebih lama'),
      ),
    );
  }
}

class _CardGroupRow extends StatelessWidget {
  const _CardGroupRow({required this.group});

  final ProposalCardGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = group.card;
    final breakdown = group.statusBreakdown;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.push(Routes.cardProposals(card.id)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 10),
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
                    card.id == unavailableProposalCard.id
                        ? 'Bid pembeli sudah tidak aktif'
                        : '${card.expansionCode.toUpperCase()} #'
                              '${card.collectorNumber}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  if (group.subtitle.isNotEmpty)
                    Text(
                      group.subtitle,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  if (breakdown.isNotEmpty)
                    Text(
                      breakdown,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  if (group.earliestExpiry != null)
                    Text(
                      'Berakhir ${formatShortDateId(group.earliestExpiry!)}',
                      style: AppTypography.caption(context.appSemantic.condMp),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (group.receivedPending > 0)
                  StatusPill(
                    label: '${group.receivedPending} menunggu',
                    color: context.appSemantic.condMp,
                  ),
                if (group.sentPending > 0) ...[
                  if (group.receivedPending > 0) const SizedBox(height: 4),
                  StatusPill(
                    label: '${group.sentPending} terkirim',
                    color: context.mutedForeground,
                  ),
                ],
              ],
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
