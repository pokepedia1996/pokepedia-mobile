import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../repository/models/listing_offer.dart';
import '../../repository/models/seller_listing.dart';

/// Ports the seller product tables (`active-table.tsx`, `inactive-table.tsx`,
/// `archive-table.tsx`) — the same columns, in the same order, scrolled
/// sideways because a phone can't show 1000dp of them at once.
///
/// Two of web's columns are absent, both for want of data rather than room:
/// "Terjual" comes from `get_seller_listings_page`, an RPC that isn't
/// deployed (`listings.sold_count` doesn't exist), and "Foto kartu" opens a
/// photo manager the app doesn't have yet — the count rides on the thumbnail
/// instead. Web's bulk-select checkbox is out too: there are no bulk actions
/// here to select for.
class ListingTable extends StatelessWidget {
  const ListingTable({
    super.key,
    required this.listings,
    required this.sort,
    required this.onSort,
    required this.onArchive,
    required this.onUnarchive,
    required this.onRestock,
    required this.onDelete,
    required this.onToggleOffers,
    required this.onToggleAutoRelist,
    required this.onViewOffers,
    required this.offerCounts,
    required this.onRefresh,
  });

  final List<SellerListing> listings;
  final ListingSort sort;
  final ValueChanged<ListingSortCol> onSort;
  final ValueChanged<SellerListing> onArchive;
  final ValueChanged<SellerListing> onUnarchive;
  final ValueChanged<SellerListing> onRestock;

  /// `delete_listing` — a soft delete the seller cannot undo from the app,
  /// which is why the page confirms before calling it.
  final ValueChanged<SellerListing> onDelete;
  final void Function(SellerListing listing, bool value) onToggleOffers;
  final void Function(SellerListing listing, bool value) onToggleAutoRelist;
  final ValueChanged<SellerListing> onViewOffers;

  /// Live offers per `listings.slug`. Empty while they load — a row with no
  /// badge yet looks exactly like a row with no offers, and neither wants a
  /// spinner in a table cell.
  final Map<String, OfferCount> offerCounts;
  final Future<void> Function() onRefresh;

  static const _columns = <_Column>[
    _Column('Aksi', 72),
    _Column('Gambar', 108),
    _Column('Nama kartu', 150, sort: ListingSortCol.name, align: _Align.left),
    _Column('Ekspansi', 74, sort: ListingSortCol.expansion),
    _Column('Nomor', 72, sort: ListingSortCol.number),
    _Column('Kondisi', 64, sort: ListingSortCol.condition),
    _Column('Harga', 100, sort: ListingSortCol.price),
    _Column('Jumlah', 84, sort: ListingSortCol.quantity),
    _Column('Harga Total', 108, align: _Align.right),
    _Column('Dilihat', 64, sort: ListingSortCol.views),
    _Column('Perpanjang Otomatis', 96),
    _Column('Terima Penawaran', 96),
  ];

  @override
  Widget build(BuildContext context) {
    return _TableShell(
      columns: _columns,
      sort: sort,
      onSort: onSort,
      onRefresh: onRefresh,
      itemCount: listings.length,
      cells: (context, i) => _listingCells(
        context,
        listings[i],
        onArchive: () => onArchive(listings[i]),
        onUnarchive: () => onUnarchive(listings[i]),
        onRestock: () => onRestock(listings[i]),
        onDelete: () => onDelete(listings[i]),
        onToggleOffers: (v) => onToggleOffers(listings[i], v),
        onToggleAutoRelist: (v) => onToggleAutoRelist(listings[i], v),
        onViewOffers: () => onViewOffers(listings[i]),
        offers: offerCounts[listings[i].slug],
      ),
    );
  }
}

/// The chrome every product table shares: a bordered card, a header that
/// scrolls sideways with the body but holds its place vertically, and rows
/// laid out on the same column widths.
class _TableShell extends StatelessWidget {
  const _TableShell({
    required this.columns,
    required this.itemCount,
    required this.cells,
    required this.onRefresh,
    this.sort,
    this.onSort,
  });

  final List<_Column> columns;
  final int itemCount;
  final List<Widget> Function(BuildContext context, int index) cells;
  final Future<void> Function() onRefresh;

  /// Null on a table with nothing to order by, which leaves its headers
  /// inert rather than tappable-but-useless.
  final ListingSort? sort;
  final ValueChanged<ListingSortCol>? onSort;

  @override
  Widget build(BuildContext context) {
    final width = columns.fold<double>(0, (sum, c) => sum + c.width);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                _HeaderRow(columns: columns, sort: sort, onSort: onSort),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: onRefresh,
                    child: ListView.builder(
                      itemCount: itemCount,
                      itemBuilder: (context, i) =>
                          _Row(columns: columns, cells: cells(context, i)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.columns, required this.cells});

  final List<_Column> columns;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        // Not `stretch`: inside a list the row's own height is unbounded, so
        // stretching the cells asks them to be infinitely tall. Web's rows
        // are `align-middle` anyway.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: columns[i].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: columns[i].rowAlignment,
                  children: [Flexible(child: cells[i])],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "Gambar" thumbnail: a landscape window onto the card rather than the
/// whole 245:342 of it.
///
/// A row of full cards at this height is a column of stamps — too small to
/// recognise, and mostly attack text. Cropping to the illustration is what
/// makes a listing identifiable at a glance, which is the only thing this
/// column is for.
const _thumbWidth = 92.0;
const _thumbAspect = 92 / 54;

/// Up towards the artwork, which sits in the card's top half. Not flush with
/// the top edge: a sliver of border and the name row is what tells one print
/// from another.
const _thumbAlignment = Alignment(0, -0.55);

enum _Align { left, center, right }

class _Column {
  const _Column(
    this.label,
    this.width, {
    this.sort,
    this.align = _Align.center,
  });

  final String label;
  final double width;

  /// Null for a column there's nothing sensible to order by.
  final ListingSortCol? sort;
  final _Align align;

  MainAxisAlignment get rowAlignment => switch (align) {
    _Align.left => MainAxisAlignment.start,
    _Align.center => MainAxisAlignment.center,
    _Align.right => MainAxisAlignment.end,
  };
}

/// Ports `SortTh` — label, and an arrow on the column currently ordering the
/// table.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.sort,
    required this.onSort,
  });

  final List<_Column> columns;
  final ListingSort? sort;
  final ValueChanged<ListingSortCol>? onSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sort = this.sort;

    return Container(
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          for (final column in columns)
            SizedBox(
              width: column.width,
              child: InkWell(
                onTap: column.sort == null || onSort == null
                    ? null
                    : () => onSort!(column.sort!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: column.rowAlignment,
                    children: [
                      Flexible(
                        child: Text(
                          column.label,
                          maxLines: 2,
                          textAlign: switch (column.align) {
                            _Align.left => TextAlign.left,
                            _Align.center => TextAlign.center,
                            _Align.right => TextAlign.right,
                          },
                          style: AppTypography.overline(
                            context.mutedForeground,
                          ),
                        ),
                      ),
                      if (sort != null && sort.col == column.sort) ...[
                        const SizedBox(width: 2),
                        Icon(
                          sort.ascending
                              ? LucideIcons.arrowUp
                              : LucideIcons.arrowDown,
                          size: 11,
                          color: colors.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One listing's cells, in the column order declared above.
List<Widget> _listingCells(
  BuildContext context,
  SellerListing listing, {
  required VoidCallback onArchive,
  required VoidCallback onUnarchive,
  required VoidCallback onRestock,
  required ValueChanged<bool> onToggleOffers,
  required ValueChanged<bool> onToggleAutoRelist,
  required VoidCallback onViewOffers,
  required VoidCallback onDelete,
  required OfferCount? offers,
}) {
  final colors = context.appColors;
  // Web disables price/quantity/condition edits while a buyer holds stock;
  // the same rows are the ones this table won't let you archive.
  final locked = listing.qtyLocked > 0;

  return <Widget>[
    _ActionsCell(
      listing: listing,
      locked: locked,
      offers: offers,
      onViewOffers: onViewOffers,
      onDelete: onDelete,
      onArchive: onArchive,
      onUnarchive: onUnarchive,
      onRestock: onRestock,
    ),
    SizedBox(
      width: _thumbWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: CardArt(
              imageUrl: listing.photoUrls.isNotEmpty
                  ? listing.photoUrls.first
                  : listing.card.imageUrl,
              borderRadius: AppRadius.xs,
              aspectRatio: _thumbAspect,
              alignment: _thumbAlignment,
            ),
          ),
          // Web gives photos their own column; here the count rides on the
          // thumbnail, since a listing over Rp100rb needs at least one and
          // its absence is what the seller is scanning for.
          if (listing.photoUrls.isNotEmpty)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.onSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Theme.of(context).cardColor),
                ),
                child: Text(
                  '${listing.photoUrls.length}',
                  style: AppTypography.badge(colors.surface),
                ),
              ),
            ),
        ],
      ),
    ),
    Text(
      listing.card.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.captionSemibold(colors.onSurface),
    ),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        listing.card.expansionCode.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.badge(context.mutedForeground),
      ),
    ),
    Text(
      '#${listing.card.collectorNumber}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(context.mutedForeground),
    ),
    ConditionBadge(condition: listing.condition, dense: true),
    Text(
      formatRupiah(listing.price),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.captionSemibold(colors.onSurface),
    ),
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          // Web shows a bare ×n until stock is locked, then the split, so
          // the seller can tell available from total at a glance.
          locked
              ? '${listing.available} / ${listing.quantity}'
              : '×${listing.quantity}',
          style: AppTypography.caption(
            listing.isOutOfStock ? colors.error : colors.onSurface,
          ),
        ),
        if (locked)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.lock, size: 9, color: context.appSemantic.gold),
              const SizedBox(width: 2),
              Text(
                '${listing.qtyLocked}',
                style: AppTypography.badge(context.appSemantic.gold),
              ),
            ],
          ),
      ],
    ),
    Text(
      formatRupiah(listing.totalValue),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(colors.onSurface),
    ),
    Text(
      '${listing.viewCount}',
      style: AppTypography.caption(
        listing.viewCount > 0
            ? colors.onSurface
            : context.mutedForeground.withValues(alpha: 0.6),
      ),
    ),
    _SwitchCell(
      value: listing.autoRelist,
      // Locked stock means a payment is running against this row.
      enabled: !listing.isArchived && !locked,
      onChanged: onToggleAutoRelist,
    ),
    _SwitchCell(
      value: listing.acceptsOffers,
      enabled: !listing.isArchived && !locked,
      onChanged: onToggleOffers,
    ),
  ];
}

/// Web's Edit button plus its row menu. Editing price, quantity and
/// condition in place isn't built on mobile yet, so this is the menu.
class _ActionsCell extends StatelessWidget {
  const _ActionsCell({
    required this.listing,
    required this.locked,
    required this.offers,
    required this.onArchive,
    required this.onUnarchive,
    required this.onRestock,
    required this.onDelete,
    required this.onViewOffers,
  });

  final SellerListing listing;
  final bool locked;
  final OfferCount? offers;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onRestock;
  final VoidCallback onDelete;
  final VoidCallback onViewOffers;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final needsResponse = offers?.needsResponse ?? 0;

    return PopupMenuButton<String>(
      tooltip: 'Aksi listing',
      padding: EdgeInsets.zero,
      // Web marks the menu itself when something inside needs answering, so
      // the row reads as "open me" without expanding every row to find out.
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(LucideIcons.ellipsis, size: 18, color: context.mutedForeground),
          if (needsResponse > 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).cardColor),
                ),
              ),
            ),
        ],
      ),
      onSelected: (value) => switch (value) {
        'offers' => onViewOffers(),
        'unarchive' => onUnarchive(),
        'restock' => onRestock(),
        'delete' => onDelete(),
        _ => onArchive(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'offers',
          child: _MenuItem(
            icon: LucideIcons.handshake,
            label: 'Lihat penawaran',
            trailing: needsResponse > 0 ? '$needsResponse' : null,
          ),
        ),
        if (listing.isArchived)
          const PopupMenuItem(
            value: 'unarchive',
            child: _MenuItem(
              icon: LucideIcons.archiveRestore,
              label: 'Kembalikan',
            ),
          )
        else ...[
          const PopupMenuItem(
            value: 'restock',
            child: _MenuItem(
              icon: LucideIcons.squarePlus,
              label: 'Tambah stok',
            ),
          ),
          PopupMenuItem(
            value: 'archive',
            // A row a buyer is paying for can't be pulled out from under
            // them, which is the same rule web enforces.
            enabled: !locked,
            child: const _MenuItem(
              icon: LucideIcons.archive,
              label: 'Arsipkan',
            ),
          ),
        ],
        PopupMenuItem(
          value: 'delete',
          enabled: !locked,
          child: _MenuItem(
            icon: LucideIcons.trash2,
            label: 'Hapus permanen',
            color: colors.error,
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String label;

  /// A count on the right, the way web badges "Lihat penawaran".
  final String? trailing;

  /// Overrides both icon and label — the destructive entry reads as one.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.mutedForeground;
    return Row(
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySm(color ?? context.appColors.onSurface),
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: context.appSemantic.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              trailing!,
              style: AppTypography.badge(context.appSemantic.gold),
            ),
          ),
      ],
    );
  }
}

class _SwitchCell extends StatelessWidget {
  const _SwitchCell({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // A full-size Switch is taller than the row; this is the same control at
    // the scale the table can carry.
    return Transform.scale(
      scale: 0.7,
      child: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Ports `draft-table.tsx`. Drafts carry no views, no stock lock and no
/// offer toggle — what they have is what still needs deciding before the
/// listing can go up, so price leads.
class DraftTable extends StatelessWidget {
  const DraftTable({
    super.key,
    required this.drafts,
    required this.onDelete,
    required this.onRefresh,
  });

  final List<SellerDraft> drafts;
  final ValueChanged<SellerDraft> onDelete;
  final Future<void> Function() onRefresh;

  static const _columns = <_Column>[
    _Column('Aksi', 56),
    _Column('Gambar', 108),
    _Column('Nama kartu', 150, align: _Align.left),
    _Column('Ekspansi', 74),
    _Column('Nomor', 72),
    _Column('Kelangkaan', 80),
    _Column('Kondisi', 64),
    _Column('Jumlah', 70),
    _Column('Harga', 100),
    _Column('Harga Total', 108, align: _Align.right),
  ];

  @override
  Widget build(BuildContext context) {
    return _TableShell(
      columns: _columns,
      onRefresh: onRefresh,
      itemCount: drafts.length,
      cells: (context, i) =>
          _draftCells(context, drafts[i], onDelete: () => onDelete(drafts[i])),
    );
  }
}

List<Widget> _draftCells(
  BuildContext context,
  SellerDraft draft, {
  required VoidCallback onDelete,
}) {
  final colors = context.appColors;
  final price = draft.price;

  return <Widget>[
    IconButton(
      onPressed: onDelete,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Hapus draft',
      icon: Icon(LucideIcons.trash2, size: 18, color: context.mutedForeground),
    ),
    SizedBox(
      width: _thumbWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: CardArt(
              imageUrl: draft.card.imageUrl,
              borderRadius: AppRadius.xs,
              aspectRatio: _thumbAspect,
              alignment: _thumbAlignment,
            ),
          ),
          if (draft.photoCount > 0)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.onSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Theme.of(context).cardColor),
                ),
                child: Text(
                  '${draft.photoCount}',
                  style: AppTypography.badge(colors.surface),
                ),
              ),
            ),
        ],
      ),
    ),
    Text(
      draft.card.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.captionSemibold(colors.onSurface),
    ),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        draft.card.expansionCode.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.badge(context.mutedForeground),
      ),
    ),
    Text(
      '#${draft.card.collectorNumber}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(context.mutedForeground),
    ),
    Text(
      draft.card.rarity ?? '-',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(context.mutedForeground),
    ),
    ConditionBadge(condition: draft.condition, dense: true),
    Text('×${draft.quantity}', style: AppTypography.caption(colors.onSurface)),
    Text(
      // The gap a draft exists to hold: no price yet means it can't be
      // posted, so it's called out rather than dashed away.
      price == null ? 'Belum diisi' : formatRupiah(price),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: price == null
          ? AppTypography.caption(colors.primary)
          : AppTypography.captionSemibold(colors.onSurface),
    ),
    Text(
      price == null ? '-' : formatRupiah(price * draft.quantity),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(colors.onSurface),
    ),
  ];
}
