import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../usecase/moderation_notifier.dart';
import 'report_user_sheet.dart';

/// Ports `user-safety-menu.tsx`: the "Opsi pengguna" button on a chat, store
/// or profile, opening Laporkan / Blokir (or Buka blokir).
///
/// [onBlockChanged] runs after a block or unblock lands, so the screen can
/// swap to its blocked state or reload.
class UserSafetyButton extends ConsumerWidget {
  const UserSafetyButton({
    super.key,
    required this.userId,
    required this.username,
    required this.reportContext,
    this.roomSlug,
    this.isBlocked = false,
    this.onBlockChanged,
  });

  final String userId;
  final String? username;
  final UserReportContext reportContext;
  final String? roomSlug;
  final bool isBlocked;
  final ValueChanged<bool>? onBlockChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Opsi pengguna',
      icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
      onPressed: () => openUserSafetyMenu(
        context,
        ref,
        userId: userId,
        username: username,
        reportContext: reportContext,
        roomSlug: roomSlug,
        isBlocked: isBlocked,
        onBlockChanged: onBlockChanged,
      ),
    );
  }
}

/// The menu itself, for screens that open it from somewhere other than
/// [UserSafetyButton].
Future<void> openUserSafetyMenu(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String? username,
  required UserReportContext reportContext,
  String? roomSlug,
  bool isBlocked = false,
  ValueChanged<bool>? onBlockChanged,
}) async {
  // Web shows the menu to signed-in viewers only; here a signed-out tap
  // goes to login, as the listing report does.
  if (ref.read(authProvider).valueOrNull == null) {
    context.push(Routes.login);
    return;
  }

  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LucideIcons.flag, size: 20),
            title: const Text('Laporkan pengguna'),
            onTap: () => Navigator.of(sheetContext).pop('report'),
          ),
          if (isBlocked)
            ListTile(
              leading: const Icon(LucideIcons.shieldCheck, size: 20),
              title: const Text('Buka blokir'),
              onTap: () => Navigator.of(sheetContext).pop('unblock'),
            )
          else
            ListTile(
              leading: Icon(
                LucideIcons.ban,
                size: 20,
                color: sheetContext.appColors.error,
              ),
              title: Text(
                'Blokir pengguna',
                style: TextStyle(color: sheetContext.appColors.error),
              ),
              onTap: () => Navigator.of(sheetContext).pop('block'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  switch (action) {
    case 'report':
      final sent = await showReportUserSheet(
        context,
        userId: userId,
        username: username,
        reportContext: reportContext,
        roomSlug: roomSlug,
      );
      if (sent) say('Laporan terkirim, terima kasih');
    case 'block':
      await showConfirmDialog(
        context,
        title: username == null ? 'Blokir pengguna ini?' : 'Blokir @$username?',
        description:
            'Kalian tidak akan bisa saling chat, melihat profil, toko, maupun '
            'listing satu sama lain. Pesanan yang sudah berjalan tetap '
            'diproses. Kamu bisa membuka blokir kapan saja di Pengaturan.',
        confirmLabel: 'Blokir',
        loadingLabel: 'Memblokir…',
        onConfirm: () async {
          try {
            await setUserBlocked(ref, userId, true);
            say('Pengguna diblokir');
            onBlockChanged?.call(true);
          } on ModerationException catch (e) {
            say(e.message);
          }
        },
      );
    case 'unblock':
      // Web unblocks straight away: undoing a block needs no warning.
      try {
        await setUserBlocked(ref, userId, false);
        say('Blokir dibuka');
        onBlockChanged?.call(false);
      } on ModerationException catch (e) {
        say(e.message);
      }
  }
}
