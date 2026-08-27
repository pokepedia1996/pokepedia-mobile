import 'dart:io';
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
  /// Wraps the off-screen poster so it can be captured to pixels.
  final _posterKey = GlobalKey();

  PosterSide _side = PosterSide.wts;
  bool _busy = false;

  String get _shareUrl => '${AppConfig.appUrl}/market/${widget.store.handle}';

  /// Paints the poster and hands back PNG bytes.
  ///
  /// The poster is laid out at a fixed 1080×1350 regardless of the phone, so
  /// `pixelRatio` is 1 here — scaling by the device ratio would produce a
  /// different image size per handset for the same design.
  Future<Uint8List?> _capture() async {
    final boundary =
        _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // A frame may not have painted yet on the first tap.
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _sharePoster() async {
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) {
        _toast('Poster belum siap, coba lagi.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/pokepedia-${widget.store.handle}-'
        '${_side.badge.toLowerCase()}.png',
      );
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          // Carried alongside the image so a recipient can reach the store
          // even where the picture is all that survives.
          text: '${widget.store.storeName} · ${_side.label} di $_shareUrl',
        ),
      );
    } catch (e) {
      _toast('Gagal membagikan poster.');
    } finally {
      if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(storeListingsProvider(widget.store.handle));
    final all = async.valueOrNull ?? const <ListingModel>[];

    // The poster advertises one side of the book at a time; the badge is the
    // toggle the sketch marks "interchangeable".
    final forSide = all.where((l) => l.side == _side.listingSide).toList();
    final shown = forSide.take(StorePoster.capacity).toList();

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
              onChanged: (s) => setState(() => _side = s),
            ),
            const SizedBox(height: 14),

            // The preview. The real poster is painted off-screen at full
            // size; this is the same widget scaled down to fit the sheet, so
            // what's previewed is exactly what gets shared.
            AspectRatio(
              aspectRatio: StorePoster.width / StorePoster.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: async.isLoading
                    ? Container(
                        color: colors.secondary,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : forSide.isEmpty
                    ? Container(
                        color: colors.secondary,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _side == PosterSide.wts
                              ? 'Toko ini belum menjual kartu apa pun.'
                              : 'Toko ini belum mencari kartu apa pun.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          key: _posterKey,
                          child: StorePoster(
                            store: widget.store,
                            listings: shown,
                            side: _side,
                            totalCount: forSide.length,
                            positivePct: widget.positivePct,
                            feedbackScore: widget.feedbackScore,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _busy || forSide.isEmpty ? null : _sharePoster,
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text(_busy ? 'Menyiapkan...' : 'Bagikan poster'),
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

/// WTS / WTB — the sketch's "interchangeable" badge.
class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.side, required this.onChanged});

  final PosterSide side;
  final ValueChanged<PosterSide> onChanged;

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
                onTap: () => onChanged(option),
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
