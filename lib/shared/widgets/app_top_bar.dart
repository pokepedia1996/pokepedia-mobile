import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../features/cart/usecase/cart_notifier.dart';

/// Whether the tab under the top bar has been scrolled past the threshold.
///
/// Written by `AppShell`, which already listens to every branch's scroll for
/// the bottom nav — one listener rather than one per page, since the bar is a
/// sibling of each page's scrollable and can't hear it directly.
final topBarScrolledProvider = StateProvider<bool>((ref) => false);

/// Shared top bar, ported from the mobile block in
/// `components/layout/navbar.tsx`: two rows, logo + cart above a
/// tap-to-search field.
///
/// On scroll the logo row folds away and its cart button slides in beside
/// the search field, the same morph the web plays with GSAP. Tapping the
/// field pushes [Routes.search] (no inline suggestions), standing in for the
/// dedicated "Pencarian" bottom-nav tab.
class AppTopBar extends ConsumerWidget {
  const AppTopBar({super.key, this.showCart = true});

  /// The cart button. On by default — Beranda and the other browsing tabs
  /// all lead to buying.
  final bool showCart;

  /// `window.scrollY > 100` in `NavbarMain`.
  static const morphThreshold = 100.0;

  /// Matches the market header's morph rather than the web's 0.4s: a phone
  /// reaches the threshold faster than a desktop scroll, so the header
  /// should be settled by the time the next row is in view.
  static const _morphDuration = Duration(milliseconds: 180);
  static const _morphCurve = Curves.easeOutCubic;

  /// The logo row's height, and the basis for its `y: -4` lift.
  static const _logoRowHeight = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrolled = ref.watch(topBarScrolledProvider);
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/horizontal-logo-dark.webp'
        : 'assets/images/horizontal-logo-light.webp';

    return DecoratedBox(
      // Opaque, like the web's `bg-background` on the mobile nav block: the
      // bar is pinned above the page, so the feed must not show through it
      // while the logo row folds away.
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The gap the web keeps above the bar in both states.
          const SizedBox(height: 8),

          // Row one — logo and cart. Collapses to nothing on scroll.
          // `heightFactor` rather than an animated height so the row is
          // clipped as it shrinks instead of overflowing its own box.
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: scrolled ? 0 : 1,
              duration: _morphDuration,
              curve: _morphCurve,
              child: AnimatedSlide(
                offset: scrolled
                    ? const Offset(0, -4 / _logoRowHeight)
                    : Offset.zero,
                duration: _morphDuration,
                curve: _morphCurve,
                child: AnimatedOpacity(
                  opacity: scrolled ? 0 : 1,
                  duration: _morphDuration,
                  curve: _morphCurve,
                  child: SizedBox(
                    height: _logoRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                      child: Row(
                        children: [
                          Image.asset(logoAsset, height: 28),
                          const Spacer(),
                          if (showCart) const _CartButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Row two — search. Its top gap closes as the logo row leaves,
          // matching the web's `marginTop: 8 -> 0`.
          AnimatedPadding(
            duration: _morphDuration,
            curve: _morphCurve,
            padding: EdgeInsets.fromLTRB(16, scrolled ? 0 : 8, 16, 8),
            child: Row(
              children: [
                const Expanded(child: _SearchField()),
                // Sits beside search because it's the same job by another
                // route: search is "I know what I'm looking for", scan is "I'm
                // holding it". Kept out of the scroll-morph the cart does — the
                // scanner is a primary action, not a contextual one.
                const _ScanButton(),
                if (showCart)
                  // The cart that takes over once the logo row's copy is gone.
                  // `widthFactor` animates the web's `width: 0 -> auto`, and
                  // `IgnorePointer` stands in for `pointerEvents: none` so the
                  // zero-width button can't be tapped.
                  IgnorePointer(
                    ignoring: !scrolled,
                    child: ClipRect(
                      child: AnimatedAlign(
                        alignment: Alignment.centerRight,
                        widthFactor: scrolled ? 1 : 0,
                        duration: _morphDuration,
                        curve: _morphCurve,
                        child: AnimatedOpacity(
                          opacity: scrolled ? 1 : 0,
                          duration: _morphDuration,
                          curve: _morphCurve,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: _CartButton(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the camera card scanner.
class _ScanButton extends StatelessWidget {
  const _ScanButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        onPressed: () => context.push(Routes.scan),
        tooltip: 'Pindai kartu',
        icon: Icon(LucideIcons.focus, color: context.appColors.onSurface),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: () => context.go(Routes.search),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 18, color: context.mutedForeground),
            const SizedBox(width: 8),
            Text(
              'Cari kartu...',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cart icon with the item-count badge, as sketched beside the search field.
class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final count = ref.watch(cartCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(LucideIcons.shoppingCart, size: 22),
          onPressed: () => context.push(Routes.cart),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: AppTypography.badge(
                  colors.onPrimary,
                ).copyWith(fontSize: 9),
              ),
            ),
          ),
      ],
    );
  }
}
