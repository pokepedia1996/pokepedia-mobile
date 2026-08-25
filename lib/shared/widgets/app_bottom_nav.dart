import 'package:flutter/material.dart';

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
    this.compact = false,
  });

  /// Matches the web's GSAP shrink: the pill scales down and settles a few
  /// pixels lower while the user scrolls down the page.
  static const _compactScale = 0.94;
  static const _compactOffsetY = 3.0;
  static const _compactDuration = Duration(milliseconds: 350);

  /// Pill height (6px padding + 8/20/2/11/8 item stack + 6px padding) and
  /// the gap it floats above the screen edge.
  static const _pillHeight = 61.0;
  static const _pillGap = 12.0;

  /// Vertical space the floating pill covers, for tabs that let their
  /// content scroll underneath it.
  ///
  /// Inside [AppShell] the shell's `extendBody: true` already reports this
  /// as the body's bottom padding, so that value wins; the constants are the
  /// fallback for anywhere the nav is measured outside the shell.
  static double reservedSpace(BuildContext context) {
    final media = MediaQuery.of(context);
    final fromScaffold = media.padding.bottom;
    final intrinsic = _pillHeight + _pillGap + media.viewPadding.bottom;
    return fromScaffold > intrinsic ? fromScaffold : intrinsic;
  }

  static const items = [
    BottomNavItem(label: 'Beranda', icon: Icons.home_outlined),
    BottomNavItem(label: 'Ekspansi', icon: Icons.circle, usePokeball: true),
    BottomNavItem(label: 'Pencarian', icon: Icons.search),
    BottomNavItem(
      label: 'Koleksi',
      icon: Icons.account_balance_wallet_outlined,
    ),
    BottomNavItem(label: 'Market', icon: Icons.storefront_outlined),
    BottomNavItem(label: 'Akun', icon: Icons.person_outline),
  ];

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Shrinks the pill — driven by [AppShell]'s scroll listener.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final reduceMotion = media.disableAnimations;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: compact && !reduceMotion ? 1 : 0),
      duration: reduceMotion ? Duration.zero : _compactDuration,
      curve: Curves.easeOutQuad,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, _compactOffsetY * t),
        child: Transform.scale(
          scale: 1 - (1 - _compactScale) * t,
          // Bottom-anchored so the pill shrinks toward the screen edge, the
          // same `transformOrigin: "bottom center"` the web uses.
          alignment: Alignment.bottomCenter,
          child: child,
        ),
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
                        item.usePokeball
                            ? PokeballIcon(size: 20, color: fg)
                            : Icon(item.icon, size: 20, color: fg),
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
