import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../core/config/app_config.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../notifications/usecase/notification_route.dart';
import '../usecase/promo_popup_controller.dart';
import 'promo_popup_dialog.dart';

/// Ports `features/promos/components/promo-popup-gate.tsx` +
/// `usePromoPopup`: wraps the home screen and, once it has settled, shows
/// the winning campaign at most once per app run.
///
/// Suppressed, like web, while the session is still resolving, while the
/// onboarding modal is owed, when the screen is not the one in front (another
/// tab, a pushed route), and when the creative fails to load.
class PromoPopupGate extends ConsumerStatefulWidget {
  const PromoPopupGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PromoPopupGate> createState() => _PromoPopupGateState();
}

class _PromoPopupGateState extends ConsumerState<PromoPopupGate> {
  /// Matches `HomeLoadingGate`'s cap, so the popup never lands on top of the
  /// Pikachu curtain — web's `useBlockingCurtain` wait.
  static const _settleDelay = Duration(seconds: 3);

  /// Web's `LOAD_GRACE_MS`: a slow creative still shows; only an error
  /// suppresses the popup.
  static const _creativeGrace = Duration(seconds: 3);

  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also fires when the tab comes back into view, via `TickerMode`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRun();
    });
  }

  bool get _inFront {
    if (!mounted) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  /// Web's `canRun`, minus the path rule: the gate only wraps the home
  /// screen, which is never one of `SUPPRESSED_PREFIXES`.
  bool get _canRun {
    final auth = ref.read(authProvider);
    if (auth.isLoading) return false;
    final user = auth.valueOrNull;
    final awaitingOnboarding = user != null && user.onboarded == false;
    return !awaitingOnboarding && _inFront;
  }

  /// Cancelled on dispose, so leaving the screen inside the settle window
  /// leaves nothing behind.
  Timer? _settleTimer;

  void _maybeRun() {
    final controller = ref.read(promoPopupControllerProvider);
    if (_running || controller.attempted || !_canRun) return;
    _running = true;
    _settleTimer = Timer(_settleDelay, _run);
  }

  Future<void> _run() async {
    final controller = ref.read(promoPopupControllerProvider);
    try {
      if (!_canRun) return;

      final isAuthed = ref.read(authProvider).valueOrNull != null;
      final popup = await controller.pick(isAuthed: isAuthed);
      if (popup == null) return;

      final creativeReady = await _creativeLoads(popup.imageUrl);
      if (!creativeReady || !_canRun) {
        controller.release();
        return;
      }

      unawaited(controller.recordShown(popup));
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => PromoPopupDialog(popup: popup),
      );

      if (accepted == true) {
        unawaited(controller.recordClicked(popup));
        await _open(popup.ctaUrl);
      } else {
        unawaited(controller.recordDismissed(popup));
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  Future<bool> _creativeLoads(String url) async {
    if (!mounted) return false;
    final loaded = Completer<bool>();
    unawaited(
      precacheImage(
        NetworkImage(url),
        context,
        onError: (_, __) {
          if (!loaded.isCompleted) loaded.complete(false);
        },
      ).then((_) {
        if (!loaded.isCompleted) loaded.complete(true);
      }),
    );
    return loaded.future.timeout(_creativeGrace, onTimeout: () => true);
  }

  /// An in-app path opens its screen; a path the app has no screen for opens
  /// on the website rather than the router's error page; an `https` URL
  /// opens outside. [ctaUrl] was sanitized when the row was read.
  Future<void> _open(String ctaUrl) async {
    if (!mounted) return;
    if (ctaUrl.startsWith('/')) {
      final route = appRouteForActionUrl(ctaUrl);
      if (route != null) {
        if (AppBottomNav.tabPaths.contains(route)) {
          context.go(route);
        } else {
          unawaited(context.push(route));
        }
        return;
      }
      await _launchExternal(Uri.parse('${AppConfig.appUrl}$ctaUrl'));
      return;
    }
    final uri = Uri.tryParse(ctaUrl);
    if (uri == null || uri.scheme != 'https') return;
    await _launchExternal(uri);
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('[promos] failed to open $uri: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The session resolving, or onboarding finishing, can unblock a run that
    // was skipped earlier.
    ref.listen(authProvider, (_, __) => _maybeRun());
    return widget.child;
  }
}
