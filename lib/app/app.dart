import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/local_push.dart';
import '../core/providers/auth_link_handler.dart';
import '../features/chat/usecase/chat_notifier.dart';
import '../features/notifications/usecase/notifications_notifier.dart';
import '../core/providers/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/notifications/usecase/notification_push_notifier.dart';
import '../shared/widgets/dismiss_keyboard_on_tap_outside.dart';
import 'router/app_router.dart';

class PokepediaApp extends ConsumerStatefulWidget {
  const PokepediaApp({super.key});

  @override
  ConsumerState<PokepediaApp> createState() => _PokepediaAppState();
}

class _PokepediaAppState extends ConsumerState<PokepediaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Realtime only hears what happens while the socket is up, so anything
  /// that arrived while the app sat in the background never reached the
  /// counters. Coming back to the foreground catches them up.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
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
      // Above the router rather than on a route: a social sign-in lands
      // wherever the user already was, and the username is owed either way.
      // The keyboard rule sits above it too, so every route, sheet and the
      // onboarding modal close the keyboard on a tap outside.
      builder: (context, child) => DismissKeyboardOnTapOutside(
        child: OnboardingGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
