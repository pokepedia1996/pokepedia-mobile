import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/market_repository.dart';
import '../../usecase/market_notifier.dart';

/// The reasons `report_listing` accepts, in web's order and wording.
///
/// Kept beside the sheet rather than in the model layer because the RPC
/// validates the same four values server-side — this list only decides what
/// the user is offered, and drifting from `REASON_OPTIONS` would show a
/// choice the database then rejects as `invalid_reason`.
const _reasons = <({String value, String label})>[
  (value: 'scam', label: 'Penipuan'),
  (value: 'counterfeit', label: 'Barang palsu'),
  (value: 'miscategorized', label: 'Salah kategori'),
  (value: 'other', label: 'Lainnya'),
];

/// `MAX_REPORT_DETAILS` — the same ceiling the route's zod schema enforces.
const _maxDetails = 1000;

/// Ports `report-listing-dialog.tsx`.
///
/// A sheet rather than a dialog because that is what the web component
/// already becomes on a phone: its modal is `items-end … rounded-t-2xl`, and
/// only widens to a centred card at the `sm:` breakpoint.
///
/// Returns true when a report was filed, so the caller can confirm it.
Future<bool> showReportListingSheet(
  BuildContext context, {
  required int listingId,
  required String cardName,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ReportListingSheet(listingId: listingId, cardName: cardName),
  );
  return sent ?? false;
}

class _ReportListingSheet extends ConsumerStatefulWidget {
  const _ReportListingSheet({required this.listingId, required this.cardName});

  final int listingId;
  final String cardName;

  @override
  ConsumerState<_ReportListingSheet> createState() =>
      _ReportListingSheetState();
}

class _ReportListingSheetState extends ConsumerState<_ReportListingSheet> {
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
          .read(marketRepositoryProvider)
          .reportListing(
            listingId: widget.listingId,
            reasonCategory: reason,
            details: _details.text,
          );
      navigator.pop(true);
    } on ListingReportException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
                          'Laporkan listing',
                          style: AppTypography.bodySemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.cardName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
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
              for (final reason in _reasons) ...[
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
                maxLength: _maxDetails,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Jelaskan masalahnya…',
                ),
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
                      // Disabled until a reason is picked, as on web: the RPC
                      // rejects anything else as `invalid_reason`.
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
                      label: Text(_submitting ? 'Mengirim…' : 'Kirim Laporan'),
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
