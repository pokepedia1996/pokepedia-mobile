import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Transparent [AppBar] carrying only a circular back button plus whatever
/// page-specific [actions] a screen needs. Page titles are intentionally
/// omitted — screens carry their own heading in the body.
class TransparentAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TransparentAppBar({super.key, this.actions, this.bottom, this.onBack});

  /// Trailing icons (wishlist, cart, refresh, ...). Rendered as-is.
  final List<Widget>? actions;

  /// Optional [TabBar]-style strip below the toolbar.
  final PreferredSizeWidget? bottom;

  /// Overrides the default pop. Useful when a page needs to confirm or clean
  /// up before leaving.
  final VoidCallback? onBack;

  /// Mirrors what [AppBar.automaticallyImplyLeading] itself checks, so root
  /// pages of a navigator get no back button at all.
  bool _canPop(BuildContext context) =>
      onBack != null || (ModalRoute.of(context)?.canPop ?? false);

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // The bar is see-through, so Flutter can't derive the status bar
      // contrast from its background — key it off the theme instead.
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: _canPop(context)
          // `maybePop` (rather than a direct pop) so pages guarding their exit
          // with a `PopScope` — e.g. the checkout WebView's in-page history —
          // keep working from the app bar too.
          ? CircularBackButton(
              onPressed: onBack ?? () => Navigator.maybePop(context),
            )
          : null,
      actions: actions,
      bottom: bottom,
    );
  }
}

/// Body wrapper for the `extendBodyBehindAppBar: true` scaffolds that pair with
/// [TransparentAppBar].
///
/// Scaffold hands such a body a top padding covering the *whole* app bar, so a
/// plain [SafeArea] would just re-insert the gap the transparent bar was meant
/// to remove. This restores the real status bar inset instead: content starts
/// right below the status bar and slides underneath the floating back button.
class AppBarOverlayBody extends StatelessWidget {
  const AppBarOverlayBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: media.viewPadding.top),
      ),
      child: SafeArea(child: child),
    );
  }
}

/// Back arrow on a circular, bordered surface so it stays readable on top of
/// artwork and scrolling content.
class CircularBackButton extends StatelessWidget {
  const CircularBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Material(
        color: Theme.of(context).cardColor.withValues(alpha: 0.9),
        shape: CircleBorder(side: BorderSide(color: context.borderColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.arrow_back, size: 20, color: colors.onSurface),
          ),
        ),
      ),
    );
  }
}
