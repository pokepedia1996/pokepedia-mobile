import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

extension AppNavigation on BuildContext {
  /// Opens [location] with Beranda underneath it.
  ///
  /// For the screens that end a flow — checkout success, the payment status
  /// page, a wallet-paid checkout. They leave with `go`, which replaces the
  /// whole stack, so sending the buyer straight to Pesanan would leave it as
  /// the only route and the next back press would close the app rather than
  /// return to the shop.
  ///
  /// `go` then `push`, in that order: `push` stacks onto whatever `go` has
  /// just made current, so the pair reads as "start at Beranda, open
  /// [location] on top of it".
  void goHomeThen(String location) {
    go(Routes.home);
    push(location);
  }
}
