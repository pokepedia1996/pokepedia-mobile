import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/auth_link_handler.dart';
import '../core/providers/theme_mode_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/onboarding_modal.dart';
import '../features/notifications/usecase/notification_push_notifier.dart';
import 'router/app_router.dart';

class PokepediaApp extends ConsumerStatefulWidget {
  const PokepediaApp({super.key});

  @override
  ConsumerState<PokepediaApp> createState() => _PokepediaAppState();
}

class _PokepediaAppState extends ConsumerState<PokepediaApp> {
  @override
  void initState() {
    super.initState();
    // Started here rather than in `main`: a link can arrive before the first
    // frame (a cold start from the email) or long after, and this outlives
    // every route either way.
    unawaited(ref.read(authLinkHandlerProvider).start());
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
      builder: (context, child) =>
          OnboardingGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
