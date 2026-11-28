import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/local_push.dart';
import '../core/providers/auth_link_handler.dart';
import '../core/providers/auth_provider.dart';
import '../features/chat/usecase/chat_notifier.dart';
import '../features/notifications/usecase/notifications_notifier.dart';
import '../core/providers/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/app_update/presentation/update_required_gate.dart';
import '../features/app_update/usecase/required_update_provider.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/notifications/presentation/widgets/in_app_banner_host.dart';
import '../features/notifications/usecase/notification_push_notifier.dart';
import '../features/referral/usecase/pending_referral.dart';
import '../shared/widgets/dismiss_keyboard_on_tap_outside.dart';
import 'router/app_router.dart';
import 'router/routes.dart';

class PokepediaApp extends ConsumerStatefulWidget {
  const PokepediaApp({super.key});

  @override
  ConsumerState<PokepediaApp> createState() => _PokepediaAppState();
}

class _PokepediaAppState extends ConsumerState<PokepediaApp>
    with WidgetsBindingObserver {
  /// For the one message no route owns: an invite opened on an account
  /// that can no longer take it.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    PendingReferral.code.addListener(_onInvite);
    // Started here rather than in `main`: a link can arrive before the first
    // frame (a cold start from the email) or long after, and this outlives
    // every route either way.
    unawaited(ref.read(authLinkHandlerProvider).start());
    WidgetsBinding.instance.addObserver(this);
    // Asked at launch, after the first frame so the sheet sits over the app.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(LocalPush.instance.requestPermission()),
    );
  }

  @override
  void dispose() {
    PendingReferral.code.removeListener(_onInvite);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// An invite link (`/r/<code>`) was opened. The code is for a new account,
  /// so it goes where one is made: signed out, the signup page; mid
  /// onboarding, the referral field already took it. An account past
  /// onboarding cannot use it any more (the server only takes a code in an
  /// account's first days, before any order), so it is said and dropped.
  Future<void> _onInvite() async {
    if (PendingReferral.code.value == null) return;
    // A cold start delivers the link before the session is read.
    final user = await ref.read(authProvider.future).catchError((_) => null);
    if (!mounted || PendingReferral.code.value == null) return;
    if (user == null) {
      appRouter.push(Routes.signup);
    } else if (user.onboarded == true) {
      await PendingReferral.clear();
      _messenger.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Kode referal hanya bisa dipakai akun baru.'),
          ),
        );
    }
  }

  /// Realtime only hears what happens while the socket is up, so anything
  /// that arrived while the app sat in the background never reached the
  /// counters. Coming back to the foreground catches them up.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(requiredUpdateProvider);
    unawaited(ref.read(notificationsProvider.notifier).refresh());
    unawaited(ref.read(chatThreadsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    // Kept alive for the life of the app: it follows the session on its own,
    // subscribing to this user's notifications and showing them.
    ref.watch(notificationPushProvider);

    return MaterialApp.router(
      title: 'pokepedia.id',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      scaffoldMessengerKey: _messenger,
      // Above the router rather than on a route: a social sign-in lands
      // wherever the user already was, and the username is owed either way.
      // The keyboard rule sits above it too, so every route, sheet and the
      // onboarding modal close the keyboard on a tap outside. The
      // notification banner sits inside the gate: onboarding covers it, and
      // it covers every route. A required update covers all of it.
      builder: (context, child) => UpdateRequiredGate(
        child: DismissKeyboardOnTapOutside(
          child: OnboardingGate(
            child: InAppBannerHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
