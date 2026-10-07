import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../repository/models/promo_popup.dart';

/// Ports `features/promos/components/promo-popup.tsx`: a square creative with
/// a close button over its corner and one CTA underneath.
///
/// Pops `true` when the user takes the offer (the creative or the CTA), and
/// `false` or nothing when they close it.
class PromoPopupDialog extends StatelessWidget {
  const PromoPopupDialog({super.key, required this.popup});

  final PromoPopup popup;

  /// Web's `max-w-[420px]`.
  static const _maxWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    void accept() => Navigator.of(context).pop(true);

    return Dialog(
      backgroundColor: Theme.of(context).cardColor,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Semantics(
                    button: true,
                    label: popup.title,
                    image: true,
                    child: GestureDetector(
                      onTap: accept,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.network(
                          popup.imageUrl,
                          fit: BoxFit.cover,
                          semanticLabel: popup.imageAlt,
                          errorBuilder: (_, __, ___) =>
                              ColoredBox(color: context.appColors.secondary),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(
                          LucideIcons.x,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: FilledButton(
                  onPressed: accept,
                  child: Text(popup.ctaLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
