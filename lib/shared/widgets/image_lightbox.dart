import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/shimmer_box.dart';
import 'app_network_image.dart';

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

/// The same overlay over several images — a listing's photos — swiped
/// between, opening on [initialIndex], with "2 / 5" to say where you are.
/// Web's `ImageLightbox` with `srcs`.
Future<void> showImageGalleryLightbox(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) {
  if (imageUrls.length < 2) {
    return showImageLightbox(context, imageUrl: imageUrls.firstOrNull);
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup gambar',
    barrierColor: Colors.black.withValues(alpha: 0.85),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => _GalleryLightbox(
      imageUrls: imageUrls,
      initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class _GalleryLightbox extends StatefulWidget {
  const _GalleryLightbox({required this.imageUrls, required this.initialIndex});

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_GalleryLightbox> createState() => _GalleryLightboxState();
}

class _GalleryLightboxState extends State<_GalleryLightbox> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: GestureDetector(
                    onTap: () {},
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: cachedNetworkImage(
                        widget.imageUrls[i],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            Image.asset(
                              'assets/images/backcard.webp',
                              fit: BoxFit.contain,
                            ),
                      ),
                    ),
                  ),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageLightbox extends StatelessWidget {
  const _ImageLightbox({required this.imageUrl, required this.heroTag});

  final String? imageUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl == null
        ? Image.asset('assets/images/backcard.webp', fit: BoxFit.contain)
        : cachedNetworkImage(
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
