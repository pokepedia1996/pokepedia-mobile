import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../notifications/usecase/notifications_notifier.dart';

/// The listing page's own header: the wordmark, the notification bell, and a
/// box that searches the seller's own workspace.
///
/// Not [AppTopBar]. That one is a shopper's bar — it carries the cart and a
/// catalog search, and neither belongs on a page about the seller's own
/// stock. What a seller wants reaching for from here is their pages, their
/// orders and their listings, so the field says so.
class SellerHeader extends ConsumerWidget {
  const SellerHeader({super.key, required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/horizontal-logo-dark.webp'
        : 'assets/images/horizontal-logo-light.webp';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Image.asset(logoAsset, height: 28),
              const Spacer(),
              const _NotificationBell(),
            ],
          ),
        ),
        // Padding(
        //   padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        //   child: _WorkspaceSearch(controller: controller, onChanged: onChanged),
        // ),
      ],
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: unread > 0 ? '$unread notifikasi belum dibaca' : 'Notifikasi',
      child: InkWell(
        onTap: () => context.push(Routes.notifications),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(LucideIcons.bell, size: 22, color: colors.onSurface),
              if (unread > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: colors.surface, width: 1.5),
                    ),
                    child: Text(
                      // Past nine the exact number stops being information
                      // and starts being a wide badge.
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: AppTypography.badge(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSearch extends StatelessWidget {
  const _WorkspaceSearch({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppTypography.bodySm(colors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Cari halaman, pesanan, listing...',
        hintStyle: AppTypography.bodySm(context.mutedForeground),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        prefixIcon: Icon(
          LucideIcons.search,
          size: 18,
          color: context.mutedForeground,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
    );
  }
}
