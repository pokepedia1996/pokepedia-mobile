import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import 'pokeball_icon.dart';

class BottomNavItem {
  const BottomNavItem({
    required this.label,
    required this.icon,
    this.usePokeball = false,
  });

  final String label;
  final IconData icon;
  final bool usePokeball;
}

/// Ports `components/layout/mobile-bottom-nav.tsx` — the floating pill nav
/// bar with the five buyer-facing tabs (Beranda/Ekspansi/Koleksi/Market/
/// Akun). Pencarian was dropped in favor of the tap-to-search field in
/// [AppTopBar], shown on Beranda/Ekspansi/Koleksi.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.hidden = false,
    this.dotted = const {},
  });

  /// How long the pill takes to leave or come back.
  ///
  /// Shorter than the shrink it replaced: this one is the difference between
  /// the nav being there and not, so it has to finish inside the flick that
  /// asked for it rather than trailing the thumb.
  static const _slideDuration = Duration(milliseconds: 220);

  /// Pill height (6px padding + 8/20/2/11/8 item stack + 6px padding) and
  /// the gap it floats above the screen edge.
  static const _pillHeight = 61.0;

  /// The gap the pill floats above the screen's bottom edge. Public because
  /// anything else pinned down there has to know whether it is sitting on
  /// the pill or on the gap above it.
  static const pillGap = 12.0;

  /// Vertical space the floating pill covers, for tabs that let their
  /// content scroll underneath it.
  ///
  /// Inside [AppShell] the shell's `extendBody: true` already reports this
  /// as the body's bottom padding, so that value wins; the constants are the
  /// fallback for anywhere the nav is measured outside the shell.
  static double reservedSpace(BuildContext context) {
    final media = MediaQuery.of(context);
    final fromScaffold = media.padding.bottom;
    final intrinsic = _pillHeight + pillGap + media.viewPadding.bottom;
    return fromScaffold > intrinsic ? fromScaffold : intrinsic;
  }

  /// Where each entry of [items] goes, in the order [AppShell] declares its
  /// branches — so the index the pill reports and the index the shell
  /// switches to are the same number by construction.
  ///
  /// Public because the nav is also rendered outside the shell, on pages
  /// pushed onto the root navigator (the pack detail page): there is no
  /// `StatefulNavigationShell` in scope to call `goBranch` on, so the tap
  /// has to name the route itself.
  static const tabPaths = [
    Routes.home,
    Routes.search,
    Routes.portfolio,
    Routes.market,
    Routes.seller,
    Routes.account,
  ];

  /// Ekspansi is gone from here: the expansions browser now opens inside
  /// Pencarian, which is where someone looking for a card was always headed
  /// anyway. Its old tab is spent on Jual instead — selling was three taps
  /// deep under Akun, which is a poor place for the thing the marketplace
  /// runs on.
  static const items = [
    BottomNavItem(label: 'Beranda', icon: LucideIcons.house),
    BottomNavItem(label: 'Pencarian', icon: LucideIcons.search),
    BottomNavItem(label: 'Portofolio', icon: LucideIcons.archive),
    BottomNavItem(label: 'Market', icon: LucideIcons.store),
    BottomNavItem(label: 'Jual', icon: LucideIcons.tag),
    BottomNavItem(label: 'Akun', icon: LucideIcons.user),
  ];

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Slides the pill off the bottom of the screen — driven by [AppShell]'s
  /// scroll listener, which sets it while the page is being scrolled down
  /// and clears it on any upward scroll.
  ///
  /// The pill used to merely shrink, which kept it over the last row of
  /// whatever was being read. Reading a grid of listings is most of what
  /// this app is for, so the nav gets out of the way entirely and comes
  /// back the moment the thumb goes the other way.
  final bool hidden;

  /// Indices of [items] that carry the unread dot — web's `ActionDot` on
  /// the Akun tab. A set rather than a flag on [BottomNavItem] because
  /// [items] is a constant and what lights the dot is live state the host
  /// owns.
  final Set<int> dotted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final reduceMotion = media.disableAnimations;

    // Far enough that the shadow clears the edge too.
    final travel = _pillHeight + pillGap + bottomInset + 8;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: hidden ? 1 : 0),
      duration: reduceMotion ? Duration.zero : _slideDuration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, travel * t),
        // A pill that is off-screen must not still be catching taps meant
        // for the content it was covering.
        child: IgnorePointer(ignoring: t > 0.5, child: child),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).scaffoldBackgroundColor.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final active = i == currentIndex;
              final fg = active ? colors.onSurface : context.mutedForeground;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  onTap: () => onTap(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? colors.secondary : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            item.usePokeball
                                ? PokeballIcon(size: 20, color: fg)
                                : Icon(item.icon, size: 20, color: fg),
                            if (dotted.contains(i))
                              const Positioned(
                                top: -4 - _NavDot.ring,
                                right: -6 - _NavDot.ring,
                                child: _NavDot(),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: AppTypography.badge(
                            fg,
                          ).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Web's `ActionDot` with `ring-2 ring-background`: an 8px primary dot whose
/// ring in the page colour separates it from the icon it overlaps.
class _NavDot extends StatelessWidget {
  const _NavDot();

  static const ring = 2.0;
  static const _size = 8.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('bottom-nav-dot'),
      width: _size + ring * 2,
      height: _size + ring * 2,
      decoration: BoxDecoration(
        color: context.appColors.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: ring,
        ),
      ),
    );
  }
}
