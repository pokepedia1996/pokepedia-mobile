import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/image_url.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../repository/custom_listings_repository.dart';
import '../../repository/models/custom_listing_form.dart';

/// "Foto" on a custom listing — web's `CustomPhotoGrid`.
///
/// Up to [customMaxPhotos], the first the cover. Several can be picked at
/// once; they upload one after another, and the rest can be called off. A
/// tap on a photo opens it whole, to turn it, make it the cover, swap it or
/// take it out.
class CustomPhotoGrid extends ConsumerStatefulWidget {
  const CustomPhotoGrid({
    super.key,
    required this.urls,
    required this.onChanged,
    required this.onUploadingChanged,
  });

  /// As stored: the seller's own Storage URLs.
  final List<String> urls;

  /// Takes a change to apply to the photos as they are when it lands, not
  /// as they were when it started: uploads finish one by one.
  final void Function(List<String> Function(List<String> previous) update)
  onChanged;
  final ValueChanged<bool> onUploadingChanged;

  @override
  ConsumerState<CustomPhotoGrid> createState() => _CustomPhotoGridState();
}

class _CustomPhotoGridState extends ConsumerState<CustomPhotoGrid> {
  bool _busy = false;
  bool _stop = false;
  ({int index, int total})? _progress;

  void _lock(bool busy) {
    setState(() {
      _busy = busy;
      if (!busy) _progress = null;
    });
    widget.onUploadingChanged(busy);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  /// Camera or gallery, then uploads. [replacing] swaps one photo for the
  /// first picked, in its place.
  Future<void> _add({String? replacing}) async {
    if (_busy) return;
    final capacity = replacing != null
        ? 1
        : customMaxPhotos - widget.urls.length;
    if (capacity <= 0) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera, size: 20),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.images, size: 20),
              title: Text(
                capacity > 1
                    ? 'Pilih dari galeri (maks. $capacity)'
                    : 'Pilih dari galeri',
              ),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // Scaled and re-encoded on the device, as web's uploader compresses
    // before sending: a phone photo is several times the 4.5MB the bucket
    // takes.
    const maxSide = 2048.0;
    const quality = 88;
    final picker = ImagePicker();
    final List<XFile> picked;
    try {
      if (source == ImageSource.camera || capacity == 1) {
        final one = await picker.pickImage(
          source: source,
          maxWidth: maxSide,
          maxHeight: maxSide,
          imageQuality: quality,
        );
        picked = [?one];
      } else {
        picked = await picker.pickMultiImage(
          maxWidth: maxSide,
          maxHeight: maxSide,
          imageQuality: quality,
          limit: capacity,
        );
      }
    } catch (_) {
      if (mounted) _toast('Tidak bisa membuka foto. Cek izin kamera/galeri.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    if (picked.length > capacity) {
      _toast(
        'Hanya $capacity foto yang bisa ditambahkan. '
        'Maksimal $customMaxPhotos foto.',
      );
    }
    final accepted = picked.take(capacity).toList();

    _stop = false;
    _lock(true);
    final repository = ref.read(customListingsRepositoryProvider);
    try {
      for (final (i, file) in accepted.indexed) {
        if (!mounted || _stop) break;
        setState(() => _progress = (index: i + 1, total: accepted.length));
        final result = await repository.uploadPhoto(await file.readAsBytes());
        if (!mounted) return;
        final url = result.url;
        if (url == null) {
          _toast(result.error ?? 'Gagal mengunggah foto. Coba lagi.');
          continue;
        }
        widget.onChanged(
          (previous) => replacing != null
              ? [for (final u in previous) u == replacing ? url : u]
              : [...previous, url].take(customMaxPhotos).toList(),
        );
      }
    } finally {
      if (mounted) _lock(false);
    }
  }

  Future<void> _open(String url) async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _PhotoSheet(
        url: url,
        index: widget.urls.indexOf(url),
        total: widget.urls.length,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PhotoAction.cover:
        widget.onChanged(
          (previous) => [url, ...previous.where((u) => u != url)],
        );
      case _PhotoAction.remove:
        widget.onChanged(
          (previous) => previous.where((u) => u != url).toList(),
        );
      case _PhotoAction.replace:
        await _add(replacing: url);
      case _PhotoAction.rotate:
        _lock(true);
        final result = await ref
            .read(customListingsRepositoryProvider)
            .rotatePhoto(url);
        if (!mounted) return;
        _lock(false);
        final rotated = result.url;
        if (rotated == null) {
          _toast(result.error ?? 'Gagal memutar foto. Coba lagi.');
          return;
        }
        widget.onChanged(
          (previous) => [for (final u in previous) u == url ? rotated : u],
        );
        // Back to the same photo, turned, for another quarter if needed.
        await _open(rotated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final urls = widget.urls;
    final progress = _progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Foto',
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
            ),
            Text(
              '${urls.length}/$customMaxPhotos',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Pilih beberapa foto sekaligus. Ketuk foto untuk melihat utuh dan '
          'mengatur sampul.',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 4 / 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (i, url) in urls.indexed)
              _PhotoTile(
                url: url,
                cover: i == 0,
                label: 'Atur foto ${i + 1}${i == 0 ? ', Sampul' : ''}',
                onTap: _busy ? null : () => _open(url),
              ),
            if (urls.length < customMaxPhotos)
              _AddTile(busy: _busy, onTap: _busy ? null : () => _add()),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mengunggah foto ${progress.index} dari ${progress.total}...',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              if (progress.total > 1)
                TextButton(
                  onPressed: _stop ? null : () => setState(() => _stop = true),
                  child: const Text('Batalkan sisanya'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.url,
    required this.cover,
    required this.label,
    required this.onTap,
  });

  final String url;
  final bool cover;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.borderColor),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                cachedNetworkImage(
                  proxyImageUrl(url) ?? url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                if (cover)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onSurface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'Sampul',
                        style: AppTypography.badge(colors.surface),
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

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: CustomPaint(
        painter: _DashedBorder(color: context.borderColor),
        child: Container(
          decoration: BoxDecoration(
            color: context.appColors.secondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: muted,
                      ),
                    )
                  : Icon(LucideIcons.camera, size: 20, color: muted),
              const SizedBox(height: 4),
              Text(
                busy ? 'Memproses...' : 'Tambah foto',
                style: AppTypography.caption(muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web's `border-dashed` on the add tile.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.md),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

enum _PhotoAction { rotate, cover, replace, remove }

/// One photo whole, and what can be done with it.
class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({
    required this.url,
    required this.index,
    required this.total,
  });

  final String url;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isCover = index == 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Foto ${index + 1} dari $total',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: MediaQuery.sizeOf(context).height * 0.4,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: cachedNetworkImage(
                proxyImageUrl(url) ?? url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_PhotoAction.rotate),
                    icon: const Icon(LucideIcons.rotateCw, size: 16),
                    label: const Text('Putar 90°'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isCover
                      ? Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.check,
                                size: 16,
                                color: context.mutedForeground,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Foto sampul',
                                style: AppTypography.bodySmSemibold(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        )
                      : FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(_PhotoAction.cover),
                          child: const Text('Jadikan sampul'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_PhotoAction.replace),
                  icon: const Icon(LucideIcons.imagePlus, size: 16),
                  label: const Text('Ganti foto'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.mutedForeground,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_PhotoAction.remove),
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: const Text('Hapus foto'),
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
