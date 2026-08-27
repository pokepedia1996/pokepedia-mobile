import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../features/cart/usecase/cart_notifier.dart';

/// Cart icon for [TransparentAppBar.actions], carrying the item-count badge —
/// the way to the cart from a detail page without walking back to the market
/// first.
///
/// Same circular, bordered treatment as `CircularBackButton` so it stays
/// readable over artwork on the pages whose body runs under the bar.
///
/// [iconKey] is where the add-to-cart flight lands; pass one on any page that
/// calls `flyToCart`.
class CartAppBarButton extends ConsumerStatefulWidget {
  const CartAppBarButton({super.key, this.iconKey});

  final GlobalKey? iconKey;

  @override
  ConsumerState<CartAppBarButton> createState() => _CartAppBarButtonState();
}

class _CartAppBarButtonState extends ConsumerState<CartAppBarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// Out and back — the icon catching what was thrown at it.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.0), weight: 1.6),
  ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final count = ref.watch(cartCountProvider);

    // Only a *growing* cart is worth celebrating; removals shouldn't bounce.
    ref.listen<int>(cartCountProvider, (previous, next) {
      if (previous != null && next > previous) _pop.forward(from: 0);
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: Theme.of(context).cardColor.withValues(alpha: 0.9),
            shape: CircleBorder(side: BorderSide(color: context.borderColor)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push(Routes.cart),
              child: SizedBox(
                key: widget.iconKey,
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 20,
                      color: colors.onSurface,
                    ),
                    if (count > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 15),
                          height: 15,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            // A three-digit cart would burst the badge.
                            count > 99 ? '99+' : '$count',
                            style: AppTypography.badge(
                              colors.onPrimary,
                            ).copyWith(fontSize: 9),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
