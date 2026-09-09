import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/shimmer_box.dart';

/// Ports `components/ui/image-lightbox.tsx` — a fullscreen dark overlay
/// showing [imageUrl] pinch-zoomable via [InteractiveViewer], dismissible
/// by tapping the backdrop, the close button, or the system back
/// gesture/button. Falls back to the bundled placeholder when [imageUrl]
/// is null, mirroring [CardArt].
Future<void> showImageLightbox(
  BuildContext context, {
  required String? imageUrl,
  String? heroTag,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup gambar',
    barrierColor: Colors.black.withValues(alpha: 0.85),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _ImageLightbox(imageUrl: imageUrl, heroTag: heroTag),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class _ImageLightbox extends StatelessWidget {
  const _ImageLightbox({required this.imageUrl, required this.heroTag});

  final String? imageUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl == null
        ? Image.asset('assets/images/backcard.webp', fit: BoxFit.contain)
        : Image.network(
            imageUrl!,
            fit: BoxFit.contain,
            // Full-size art over a slow connection is the longest wait in
            // the app; a card-shaped shimmer says it is coming.
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const AspectRatio(
                    aspectRatio: 245 / 342,
                    child: ShimmerBox(),
                  ),
            errorBuilder: (context, error, stackTrace) =>
                Image.asset('assets/images/backcard.webp', fit: BoxFit.contain),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: GestureDetector(
                  onTap: () {},
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: heroTag == null
                        ? image
                        : Hero(tag: heroTag!, child: image),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
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
