import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `components/ui/confirm-dialog.tsx` — a modal with a title,
/// optional description, and cancel/confirm actions. [onConfirm] may be
/// async; the dialog shows [loadingLabel] on the confirm button while it
/// awaits and pops itself afterwards.
Future<void> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? description,
  String confirmLabel = 'Hapus',
  String loadingLabel = 'Memproses...',
  String cancelLabel = 'Batal',
  bool destructive = true,
  required Future<void> Function() onConfirm,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ConfirmDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      loadingLabel: loadingLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      onConfirm: onConfirm,
    ),
  );
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.loadingLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.onConfirm,
  });

  final String title;
  final String? description;
  final String confirmLabel;
  final String loadingLabel;
  final String cancelLabel;
  final bool destructive;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _loading = false;

  Future<void> _handleConfirm() async {
    setState(() => _loading = true);
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: !_loading,
      child: Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: AppTypography.h3(colors.onSurface)),
              if (widget.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.description!,
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(widget.cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _handleConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.destructive
                            ? colors.error
                            : colors.primary,
                      ),
                      child: _loading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    widget.loadingLabel,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : Text(widget.confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
