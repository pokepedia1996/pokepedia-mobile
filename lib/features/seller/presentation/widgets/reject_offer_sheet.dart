import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// The seller's optional note, boxed so "dismissed" and "rejected with no
/// note" stay distinguishable — both would otherwise arrive as null.
class RejectOfferNote {
  const RejectOfferNote(this.value);

  final String? value;
}

/// Ports `reject-offer-modal.tsx`. The note is optional and the only field;
/// web collects no reason code, and `reject_offer` takes a null `p_reason`.
Future<RejectOfferNote?> showRejectOfferSheet(BuildContext context) {
  return showModalBottomSheet<RejectOfferNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _RejectOfferSheet(),
  );
}

class _RejectOfferSheet extends StatefulWidget {
  const _RejectOfferSheet();

  @override
  State<_RejectOfferSheet> createState() => _RejectOfferSheetState();
}

class _RejectOfferSheetState extends State<_RejectOfferSheet> {
  final _note = TextEditingController();

  static const _maxNoteLength = 500;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tolak Penawaran',
                          style: AppTypography.h3(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Beri tahu pembeli alasannya (opsional).',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _note,
                autofocus: true,
                maxLength: _maxNoteLength,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Catatan untuk pembeli',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(RejectOfferNote(_note.text)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Tolak Penawaran'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
