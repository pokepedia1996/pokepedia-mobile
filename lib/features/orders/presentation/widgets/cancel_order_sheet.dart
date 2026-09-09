import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/pokepedia_api.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/order_cancel_repository.dart';

/// `MAX` on web's detail box, and the route's own zod ceiling.
const _maxDetail = 1000;

/// Ports the reason step of `cancel-flow-modal.tsx` for the buyer's
/// "Batalkan Pesanan".
///
/// Only the package scope: web additionally offers a per-item pick, but only
/// on multi-item orders, and it drives the same route once per chosen item.
/// This cancels the whole order, which is what the button says.
///
/// Returns null if the sheet was dismissed, otherwise whether the
/// cancellation took effect immediately (rather than going to the seller).
Future<bool?> showCancelOrderSheet(
  BuildContext context, {
  required String itemSlug,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CancelOrderSheet(itemSlug: itemSlug),
  );
}

class _CancelOrderSheet extends ConsumerStatefulWidget {
  const _CancelOrderSheet({required this.itemSlug});

  final String itemSlug;

  @override
  ConsumerState<_CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends ConsumerState<_CancelOrderSheet> {
  final _detail = TextEditingController();
  CancelReason _reason = CancelReason.fallback;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  /// Web's `canSubmit`: everything but "Lainnya" goes without explanation.
  bool get _canSubmit =>
      _reason != CancelReason.other || _detail.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    try {
      final instant = await ref
          .read(orderCancelRepositoryProvider)
          .requestCancel(
            itemSlug: widget.itemSlug,
            reason: _reason,
            detail: _detail.text,
          );
      navigator.pop(instant);
    } on ApiException catch (e) {
      // The route already answers in Indonesian ("Penjual sudah memproses
      // pesanan", "Permintaan pembatalan sudah ada"), so it is shown as-is
      // and kept in the sheet — the reason may simply need changing.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Gagal membatalkan pesanan. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final needsDetail = _reason == CancelReason.other;

    return Padding(
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
                            'Batalkan Pesanan',
                            style: AppTypography.bodySemibold(colors.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Seluruh pesanan dibatalkan dan dana '
                            'dikembalikan penuh.',
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
                          : () => Navigator.of(context).pop(),
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
                for (final reason in CancelReason.values) ...[
                  _ReasonOption(
                    label: reason.label,
                    selected: _reason == reason,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _reason = reason),
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
                      needsDetail
                          ? 'Wajib diisi untuk alasan Lainnya'
                          : 'Opsional',
                      style: AppTypography.caption(
                        needsDetail
                            ? colors.error
                            : context.mutedForeground.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _detail,
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: _maxDetail,
                  // Rebuilds so the submit button follows the "Lainnya" rule
                  // as the buyer types rather than only on the next tap.
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Jelaskan singkat...',
                  ),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 4),
                  Text(error, style: AppTypography.caption(colors.error)),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 6),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Batal'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting || !_canSubmit ? null : _submit,
                        // Web's destructive variant: a tint with a red
                        // border and red label, not a solid red block.
                        style: ElevatedButton.styleFrom(
                          foregroundColor: colors.error,
                          backgroundColor: colors.error.withValues(alpha: 0.10),
                          side: BorderSide(
                            color: colors.error.withValues(alpha: 0.20),
                          ),
                        ),
                        child: _submitting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.error,
                                ),
                              )
                            : const Text(
                                'Batalkan Pesanan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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

/// One reason row, matching the report sheet's option styling.
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
