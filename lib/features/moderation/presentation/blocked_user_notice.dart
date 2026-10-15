import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../usecase/moderation_notifier.dart';

/// Ports `blocked-user-notice.tsx`: what the blocker sees where a store or
/// profile they blocked would be. The blocked side just gets "not found".
class BlockedUserNotice extends ConsumerStatefulWidget {
  const BlockedUserNotice({
    super.key,
    required this.userId,
    required this.username,
    required this.onUnblocked,
  });

  final String userId;
  final String? username;
  final VoidCallback onUnblocked;

  @override
  ConsumerState<BlockedUserNotice> createState() => _BlockedUserNoticeState();
}

class _BlockedUserNoticeState extends ConsumerState<BlockedUserNotice> {
  bool _busy = false;

  Future<void> _unblock() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await setUserBlocked(ref, widget.userId, false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Blokir dibuka')));
      widget.onUnblocked();
    } on ModerationException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.ban, size: 40, color: context.mutedForeground),
          const SizedBox(height: 12),
          Text(
            widget.username == null
                ? 'Kamu memblokir pengguna ini'
                : 'Kamu memblokir @${widget.username}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'Profil, toko, dan listing pengguna ini disembunyikan, dan kalian '
            'tidak bisa saling chat.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _unblock,
            child: Text(_busy ? 'Membuka…' : 'Buka blokir'),
          ),
        ],
      ),
    );
  }
}
