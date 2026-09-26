import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../expansions/usecase/trading_notifier.dart';
import '../../repository/models/seller_listing.dart';
import '../../repository/seller_listings_repository.dart';

/// Photos of the actual copy, behind the camera badge on a draft card.
///
/// A listing of Rp100.000 or more is refused without one, so this is not a
/// flourish — it is the other half of what stops a draft being postable, and
/// the badge on the thumbnail is the only place it could belong.
///
/// Returns true when the draft's photos changed.
Future<bool?> showDraftPhotoSheet(BuildContext context, SellerDraft draft) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _DraftPhotoSheet(draft: draft),
  );
}

/// What `place_order` accepts, mirrored from the ask form.
const _maxPhotos = 4;

class _DraftPhotoSheet extends ConsumerStatefulWidget {
  const _DraftPhotoSheet({required this.draft});

  final SellerDraft draft;

  @override
  ConsumerState<_DraftPhotoSheet> createState() => _DraftPhotoSheetState();
}

class _DraftPhotoSheetState extends ConsumerState<_DraftPhotoSheet> {
  /// Already uploaded, by URL.
  late final List<String> _existing = [...widget.draft.photoUrls];

  /// Picked in this sitting, not yet uploaded.
  final List<File> _added = [];

  bool _saving = false;

  int get _total => _existing.length + _added.length;

  Future<void> _pick(ImageSource source) async {
    if (_total >= _maxPhotos) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _added.add(File(picked.path)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final urls = [..._existing];
    if (_added.isNotEmpty) {
      // Uploaded first, then written as one list: a draft whose row points
      // at a file that failed to upload would show a broken photo it could
      // never be rid of.
      final uploaded = await ref
          .read(tradingRepositoryProvider)
          .uploadListingPhotos(_added);
      urls.addAll(uploaded);
    }

    final error = await ref
        .read(sellerListingsRepositoryProvider)
        .setDraftPhotos(widget.draft.id, urls);

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Foto kartu',
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                ),
                Text(
                  '$_total/$_maxPhotos',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Foto kondisi asli kartumu. Listing Rp100.000 ke atas wajib '
              'punya minimal satu foto.',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 14),

            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final url in _existing)
                    _Thumb(
                      image: Image.network(url, fit: BoxFit.cover),
                      onRemove: () => setState(() => _existing.remove(url)),
                    ),
                  for (final file in _added)
                    _Thumb(
                      image: Image.file(file, fit: BoxFit.cover),
                      onRemove: () => setState(() => _added.remove(file)),
                    ),
                  if (_total < _maxPhotos) _AddTile(onTap: _showSourcePicker),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  foregroundColor: Theme.of(context).cardColor,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Simpan foto'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera, size: 20),
              title: const Text('Ambil foto'),
              onTap: () {
                Navigator.of(sheet).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.image, size: 20),
              title: const Text('Pilih dari galeri'),
              onTap: () {
                Navigator.of(sheet).pop();
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.onRemove});

  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 72,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(width: 72, height: 80, child: image),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: context.appColors.onSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).cardColor,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.x,
                    size: 12,
                    color: Theme.of(context).cardColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 72,
        height: 80,
        decoration: BoxDecoration(
          color: context.mutedForeground.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(LucideIcons.plus, size: 20, color: context.mutedForeground),
      ),
    );
  }
}
