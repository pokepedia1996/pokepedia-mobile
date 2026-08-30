import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/models/store_model.dart';
import '../../usecase/market_notifier.dart';
import 'store_poster.dart';

/// Opens the store share sheet — a poster of what the store is selling or
/// buying, ready to post, plus the plain link for people who just want that.
Future<void> showStoreShareSheet(
  BuildContext context, {
  required StoreModel store,
  double? positivePct,
  int feedbackScore = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => StoreShareSheet(
      store: store,
      positivePct: positivePct,
      feedbackScore: feedbackScore,
    ),
  );
}

class StoreShareSheet extends ConsumerStatefulWidget {
  const StoreShareSheet({
    super.key,
    required this.store,
    this.positivePct,
    this.feedbackScore = 0,
  });

  final StoreModel store;
  final double? positivePct;
  final int feedbackScore;

  @override
  ConsumerState<StoreShareSheet> createState() => _StoreShareSheetState();
}

class _StoreShareSheetState extends ConsumerState<StoreShareSheet> {
  /// One capture boundary per page, so any page can be snapshotted the
  /// moment it is the one on screen.
  final _keys = <int, GlobalKey>{};
  final _controller = PageController(viewportFraction: 0.74);

  PosterSide _side = PosterSide.wts;
  bool _busy = false;

  /// The page the carousel is resting on.
  int _page = 0;

  /// Pages that are going out. Opens holding page one alone: that poster
  /// already points at everything it leaves out, so it stands on its own,
  /// and posting a store's whole book unasked is the rarer intent.
  final _selected = <int>{0};

  /// Progress copy while a batch is running.
  String? _progress;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _shareUrl => '${AppConfig.appUrl}/market/${widget.store.handle}';

  GlobalKey _keyFor(int page) => _keys.putIfAbsent(page, GlobalKey.new);

  List<int> _selection(int pageCount) => [
    for (var i = 0; i < pageCount; i++)
      if (_selected.contains(i)) i,
  ];

  void _toggle(int page) {
    setState(() {
      if (!_selected.remove(page)) _selected.add(page);
    });
  }

  /// Paints one page and hands back PNG bytes.
  ///
  /// The poster is laid out at a fixed 1080×1350 regardless of the phone, so
  /// `pixelRatio` is 1 here — scaling by the device ratio would produce a
  /// different image size per handset for the same design.
  Future<Uint8List?> _capture(int page) async {
    final boundary =
        _keyFor(page).currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // A frame may not have painted yet on the first tap.
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  /// Captures every selected page and hands them to the share sheet as one
  /// set of files.
  Future<void> _shareSelected(int pageCount) async {
    final selection = _selection(pageCount);
    if (selection.isEmpty) return;

    setState(() => _busy = true);
    final files = <XFile>[];
    final dir = await getTemporaryDirectory();

    try {
      for (var i = 0; i < selection.length; i++) {
        if (!mounted) return;
        final page = selection[i];
        setState(() {
          _progress = selection.length == 1
              ? 'Menyiapkan...'
              : 'Menyiapkan ${i + 1} dari ${selection.length}...';
        });

        // The carousel only keeps the current page and its neighbours alive,
        // so the page being captured has to be the one on screen. Moving
        // there doubles as progress the user can watch.
        if (_controller.hasClients && _page != page) {
          _controller.jumpToPage(page);
        }
        await WidgetsBinding.instance.endOfFrame;

        final bytes = await _capture(page);
        if (bytes == null) continue;

        final file = File(
          '${dir.path}/pokepedia-${widget.store.handle}-'
          '${_side.badge.toLowerCase()}-${page + 1}.png',
        );
        await file.writeAsBytes(bytes);
        files.add(XFile(file.path));
      }

      if (files.isEmpty) {
        _toast('Poster belum siap, coba lagi.');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: files,
          // Carried alongside the images so a recipient can reach the store
          // even where the picture is all that survives.
          text: '${widget.store.storeName} · ${_side.label} di $_shareUrl',
        ),
      );
    } catch (_) {
      _toast('Gagal membagikan poster.');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    _toast('Link toko disalin');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Widget _posterPage(
    int index,
    List<List<ListingModel>> pages,
    int total, {
    bool selectable = true,
  }) {
    return _PosterPage(
      boundaryKey: _keyFor(index),
      selected: _selected.contains(index),
      selectable: selectable && !_busy,
      onTap: () => _toggle(index),
      poster: StorePoster(
        store: widget.store,
        listings: pages[index],
        side: _side,
        totalCount: posterPageTotal(pages, index, total),
        positivePct: widget.positivePct,
        feedbackScore: widget.feedbackScore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(storeListingsProvider(widget.store.handle));
    final all = async.valueOrNull ?? const <ListingModel>[];

    // The poster advertises one side of the book at a time; the badge is the
    // toggle the sketch marks "interchangeable".
    final forSide = all.where((l) => l.side == _side.listingSide).toList();
    final pages = paginateForPoster(forSide);
    // A refresh can shorten the run of pages; indices past the end are
    // already ignored when sharing, and the bar has to ignore them too or it
    // counts posters that are no longer there.
    final selection = _selection(pages.length).toSet();

    // The carousel shows a poster at a time with its neighbours peeking in,
    // so the height follows the item width rather than the sheet's. A store
    // that fits on one poster has no neighbours and gets the full width.
    final size = MediaQuery.sizeOf(context);
    final sheetWidth = size.width - 40;
    final itemWidth = pages.length > 1
        ? sheetWidth * _controller.viewportFraction
        : sheetWidth;
    // A poster is taller than it is wide, so on a short handset the width
    // alone would push the buttons off the bottom of the sheet. The cap
    // wins there and the poster simply sits narrower — `_PosterPage` keeps
    // its frame on the art either way.
    // 0.38 rather than a half: the header, the side toggle, the page bar,
    // the select pair and two buttons all share this sheet, and the poster
    // is the one part that can give ground without losing anything.
    final railHeight = math.min(
      itemWidth * StorePoster.height / StorePoster.width,
      size.height * 0.38,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Bagikan ke media sosialmu!',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),

            _SideToggle(
              side: _side,
              // Locked mid-batch: flipping sides would swap the listings out
              // from under a capture already in flight, and the pages either
              // side of the flip would belong to different posters.
              onChanged: _busy
                  ? null
                  : (s) => setState(() {
                      _side = s;
                      // A different side is a different set of pages, so the
                      // old page-index selection means nothing here.
                      _selected
                        ..clear()
                        ..add(0);
                      _page = 0;
                      if (_controller.hasClients) _controller.jumpToPage(0);
                    }),
            ),
            const SizedBox(height: 14),

            // Every page the store's listings fill, laid out to swipe
            // through. The posters are painted at full size and scaled down
            // here, so what's previewed is exactly what gets shared.
            SizedBox(
              height: railHeight,
              child: async.isLoading
                  ? _Placeholder(
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : pages.isEmpty
                  ? _Placeholder(
                      child: Text(
                        _side == PosterSide.wts
                            ? 'Toko ini belum menjual kartu apa pun.'
                            : 'Toko ini belum mencari kartu apa pun.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    )
                  // A lone poster has nothing to be picked out of, so it
                  // skips the carousel and takes the full width.
                  : pages.length == 1
                  ? _posterPage(0, pages, forSide.length, selectable: false)
                  : PageView.builder(
                      controller: _controller,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) =>
                          _posterPage(i, pages, forSide.length),
                    ),
            ),

            if (pages.length > 1) ...[
              const SizedBox(height: 10),
              _PageBar(
                page: _page,
                pageCount: pages.length,
                selected: selection,
              ),
              const SizedBox(height: 10),
              _BulkSelect(
                // Each is dead when it would change nothing, so the pair
                // also reads as the current state at a glance.
                onSelectAll: _busy || selection.length == pages.length
                    ? null
                    : () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(List.generate(pages.length, (i) => i));
                      }),
                onClear: _busy || selection.isEmpty
                    ? null
                    : () => setState(_selected.clear),
              ),
            ],
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _busy || selection.isEmpty
                  ? null
                  : () => _shareSelected(pages.length),
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text(
                _progress ??
                    (selection.isEmpty
                        ? 'Pilih poster dulu'
                        : selection.length > 1
                        ? 'Bagikan ${selection.length} poster'
                        : 'Bagikan poster'),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Salin link toko'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One poster in the carousel, with the control that keeps it in or out of
/// the share.
class _PosterPage extends StatelessWidget {
  const _PosterPage({
    required this.boundaryKey,
    required this.poster,
    required this.selected,
    required this.selectable,
    required this.onTap,
  });

  final GlobalKey boundaryKey;
  final Widget poster;
  final bool selected;
  final bool selectable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final off = selectable && !selected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: selectable ? onTap : null,
        behavior: HitTestBehavior.opaque,
        // The slot can be wider than the scaled poster once the height is
        // capped; the frame, the dimming and the tick belong to the art.
        child: Center(
          child: AspectRatio(
            aspectRatio: StorePoster.width / StorePoster.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The boundary wraps the poster and nothing else: the dimming
                // and the tick below are sheet furniture, and capturing them
                // would put them in the shared image.
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(key: boundaryKey, child: poster),
                  ),
                ),
                if (off)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).cardColor.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                if (selectable)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _SelectTick(selected: selected, colors: colors),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The in-or-out tick on a poster.
class _SelectTick extends StatelessWidget {
  const _SelectTick({required this.selected, required this.colors});

  final bool selected;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.white,
        border: Border.all(
          color: selected ? colors.primary : const Color(0x33000000),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: selected
          ? Icon(Icons.check, size: 15, color: colors.onPrimary)
          : null,
    );
  }
}

/// Which page is showing, how many are going out, and the way back to all
/// of them.
/// Which page is showing and how many are going out.
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.page,
    required this.pageCount,
    required this.selected,
  });

  final int page;
  final int pageCount;
  final Set<int> selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        // A dot per page, filled when the page is going out — the count and
        // the position in one glance. Scrollable because ten dots and a
        // count do not always fit across a narrow handset.
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < pageCount; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      width: i == page ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: selected.contains(i)
                            ? colors.primary
                            : context.borderColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${selected.length}/$pageCount dipilih',
          style: AppTypography.caption(context.mutedForeground),
        ),
      ],
    );
  }
}

/// Select-all and clear, side by side.
///
/// Full-width buttons rather than the inline link this replaced: picking ten
/// posters one tap at a time is the case these exist for, and a link sized
/// to its text is the hardest thing on the sheet to hit.
class _BulkSelect extends StatelessWidget {
  const _BulkSelect({required this.onSelectAll, required this.onClear});

  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(42),
      textStyle: AppTypography.bodySm(context.appColors.onSurface),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onSelectAll,
            style: style,
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Pilih semua'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onClear,
            style: style,
            icon: const Icon(Icons.remove_done, size: 16),
            label: const Text('Batal pilih'),
          ),
        ),
      ],
    );
  }
}

/// The loading and empty stand-ins, sized like a poster so the sheet does
/// not jump when the listings land.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: StorePoster.width / StorePoster.height,
        child: Container(
          decoration: BoxDecoration(
            color: context.appColors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

/// WTS / WTB — the sketch's "interchangeable" badge.
class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.side, required this.onChanged});

  final PosterSide side;
  final ValueChanged<PosterSide>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final option in PosterSide.values)
            Expanded(
              child: GestureDetector(
                onTap: onChanged == null ? null : () => onChanged!(option),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: option == side
                        ? Theme.of(context).cardColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${option.badge} · ${option.label}',
                    style: option == side
                        ? AppTypography.captionSemibold(colors.onSurface)
                        : AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
