import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/errors/user_message.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../usecase/moderation_notifier.dart';

/// Ports `report-user-dialog.tsx`, laid out like the listing report sheet
/// (`report_listing_sheet.dart`) — the same sheet a phone gets on web.
///
/// Returns true when a report was filed, so the caller can confirm it.
Future<bool> showReportUserSheet(
  BuildContext context, {
  required String userId,
  required String? username,
  required UserReportContext reportContext,
  String? roomSlug,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportUserSheet(
      userId: userId,
      username: username,
      reportContext: reportContext,
      roomSlug: roomSlug,
    ),
  );
  return sent ?? false;
}

class _ReportUserSheet extends ConsumerStatefulWidget {
  const _ReportUserSheet({
    required this.userId,
    required this.username,
    required this.reportContext,
    required this.roomSlug,
  });

  final String userId;
  final String? username;
  final UserReportContext reportContext;
  final String? roomSlug;

  @override
  ConsumerState<_ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends ConsumerState<_ReportUserSheet> {
  final _details = TextEditingController();
  String? _reason;
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(moderationRepositoryProvider)
          .reportUser(
            userId: widget.userId,
            reason: reason,
            context: widget.reportContext,
            details: _details.text,
            roomSlug: widget.roomSlug,
          );
      navigator.pop(true);
    } on ModerationException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('Gagal mengirim laporan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      // Lifts the sheet clear of the keyboard once the detail field has focus.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: SafeArea(
          top: false,
          // Six reasons and the footnote outgrow a short phone once the
          // keyboard is up; scroll rather than overflow.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Laporkan pengguna',
                            style: AppTypography.bodySemibold(colors.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.username == null
                                ? 'Pengguna'
                                : '@${widget.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(LucideIcons.x, size: 20),
                      color: context.mutedForeground,
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Alasan',
                  style: AppTypography.caption(context.mutedForeground),
                ),
                const SizedBox(height: 6),
                for (final reason in userReportReasons) ...[
                  _ReasonOption(
                    label: reason.label,
                    selected: _reason == reason.value,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _reason = reason.value),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Detail ',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    Text(
                      '(opsional)',
                      style: AppTypography.caption(
                        context.mutedForeground.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _details,
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: maxUserReportDetails,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Jelaskan masalahnya…',
                  ),
                ),
                Text(
                  'Tim kami meninjau setiap laporan maksimal 24 jam.',
                  style: AppTypography.caption(context.mutedForeground),
                ),
                const SizedBox(height: 10),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton.icon(
                        // Disabled until a reason is picked, as on web.
                        onPressed: _submitting || _reason == null
                            ? null
                            : _submit,
                        // Web's destructive variant: a tint with a red
                        // border and red label, not a solid red block.
                        style: ElevatedButton.styleFrom(
                          foregroundColor: colors.error,
                          backgroundColor: colors.error.withValues(alpha: 0.10),
                          side: BorderSide(
                            color: colors.error.withValues(alpha: 0.20),
                          ),
                        ),
                        icon: _submitting
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.error,
                                ),
                              )
                            : const Icon(LucideIcons.send, size: 14),
                        label: Text(
                          _submitting ? 'Mengirim…' : 'Kirim Laporan',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One reason row — web's bordered button, tinted when it is the pick.
class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
          color: selected
              ? colors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: AppTypography.bodySmSemibold(
            selected ? colors.onSurface : context.mutedForeground,
          ),
        ),
      ),
    );
  }
}
