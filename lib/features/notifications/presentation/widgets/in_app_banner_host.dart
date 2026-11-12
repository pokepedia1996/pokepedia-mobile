import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/models/notification_model.dart';
import '../../usecase/in_app_banner_notifier.dart';
import '../../usecase/notification_push_notifier.dart';
import '../../usecase/notification_route.dart';
import '../../usecase/notifications_notifier.dart';
import 'notification_icon.dart';

/// Lays the in-app banner over [child].
///
/// Mounted from `MaterialApp.router`'s builder, so the banner sits above
/// every route, sheet and tab alike — a notification can arrive over any of
/// them. That level is outside the router's Navigator, which is why the
/// banner brings its own [Material] and keeps clear of anything needing an
/// Overlay (a tooltip would assert).
class InAppBannerHost extends ConsumerStatefulWidget {
  const InAppBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppBannerHost> createState() => _InAppBannerHostState();
}

class _InAppBannerHostState extends ConsumerState<InAppBannerHost> {
  /// What the banner last showed. Kept after the provider clears so it can
  /// slide away with its text still on it, rather than emptying first.
  NotificationModel? _last;

  static const _motion = Duration(milliseconds: 250);

  void _open(NotificationModel notification) {
    ref.read(inAppBannerProvider.notifier).dismiss();
    unawaited(
      ref.read(notificationsProvider.notifier).markRead(notification.id),
    );
    final route = appRouteForActionUrl(notification.actionUrl);
    if (route != null) ref.read(notificationRouteOpenerProvider)(route);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(inAppBannerProvider);
    if (current != null) _last = current;
    final shown = _last;
    final visible = current != null;

    return Stack(
      children: [
        widget.child,
        if (shown != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                // Gone means untouchable: it is still in the tree while it
                // slides out, over whatever the user reaches for next.
                child: IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedSlide(
                    offset: visible ? Offset.zero : const Offset(0, -1.5),
                    duration: _motion,
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: _motion,
                      onEnd: () {
                        if (!visible && mounted) setState(() => _last = null);
                      },
                      child: _BannerCard(
                        notification: shown,
                        onTap: () => _open(shown),
                        onDismiss: () =>
                            ref.read(inAppBannerProvider.notifier).dismiss(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final title = notification.title.isEmpty
        ? 'pokepedia.id'
        : notification.title;

    return Semantics(
      container: true,
      liveRegion: true,
      child: GestureDetector(
        // Flicked up and away, the way a phone's own banners go.
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < 0) onDismiss();
        },
        child: Material(
          color: Theme.of(context).cardColor,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: context.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      notificationIcon(notification.type),
                      size: 18,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        if (notification.body.isNotEmpty)
                          Text(
                            notification.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // No tooltip: this sits above the router's Overlay.
                  Semantics(
                    button: true,
                    label: 'Tutup notifikasi',
                    child: InkResponse(
                      onTap: onDismiss,
                      radius: 20,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          LucideIcons.x,
                          size: 16,
                          color: context.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
