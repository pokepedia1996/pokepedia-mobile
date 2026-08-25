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
/// The page still paints edge to edge — backgrounds and artwork run under the
/// status bar and the transparent bar — but its content is inset past both,
/// clearing the floating back button and any [TransparentAppBar.actions]
/// instead of starting underneath them.
///
/// The inset has to come from the view rather than the ambient [MediaQuery]:
/// Scaffold builds the body with `removeTopPadding: appBar != null`, and
/// [MediaQueryData.removePadding] zeroes `viewPadding.top` along with
/// `padding.top` — so inside the body both read 0 and any [SafeArea] here is
/// a no-op. [MediaQueryData.fromView] is unaffected by those removals. The
/// toolbar strip is then added on top, since Scaffold has already taken it
/// out of the body's padding as well.
class AppBarOverlayBody extends StatelessWidget {
  const AppBarOverlayBody({
    super.key,
    required this.child,
    this.reserveToolbar,
    this.appBarBottomHeight = 0,
  });

  final Widget child;

  /// Whether to clear the toolbar row. Defaults to reserving it exactly when
  /// [TransparentAppBar] would draw its back button — a root page with a
  /// bare bar has nothing up there to collide with, and reserving anyway
  /// would open a 56dp hole at the top of the screen.
  ///
  /// Pass true explicitly for a page whose bar carries actions but cannot
  /// pop, and false for one that genuinely wants content behind the bar.
  final bool? reserveToolbar;

  /// Height of [TransparentAppBar.bottom], when the page gives its bar a tab
  /// strip. The body can't see the bar's own widgets, so a page with a
  /// `bottom` has to declare its height here to be cleared too.
  final double appBarBottomHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final statusBarHeight =
        MediaQueryData.fromView(View.of(context)).padding.top;

    // Mirrors `TransparentAppBar._canPop`. `onBack` forces a back button on a
    // route that can't pop; such a page passes [reserveToolbar] itself.
    final reserve =
        reserveToolbar ?? (ModalRoute.of(context)?.canPop ?? false);
    final topInset =
        statusBarHeight +
        (reserve ? kToolbarHeight + appBarBottomHeight : 0);

    return MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(top: topInset)),
      // Consumes the corrected top inset, and keeps whatever bottom/side
      // insets the scaffold handed down (home indicator, notches).
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
