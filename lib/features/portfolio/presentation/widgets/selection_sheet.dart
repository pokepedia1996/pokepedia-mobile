import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// The batch bar that rises when cards are ticked in Kelola mode: how many
/// are selected, and a three-dot menu with what can be done to them.
///
/// Shared by the collection and the wishlist, which offer the same three
/// actions over different sources.
class SelectionSheet extends StatelessWidget {
  const SelectionSheet({
    super.key,
    required this.count,
    required this.busy,
    required this.canMove,
    this.moveHint,
    required this.onCopy,
    required this.onMove,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final bool busy;

  /// Moving means "out of the source on screen", which the whole collection
  /// isn't — there, only copying makes sense.
  final bool canMove;

  /// Why moving is unavailable, shown under the greyed row.
  final Widget? moveHint;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      offset: count == 0 ? const Offset(0, 1.4) : Offset.zero,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: count == 0 ? 0 : 1,
        child: IgnorePointer(
          ignoring: count == 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: Theme.of(context).cardColor,
              elevation: 8,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$count kartu dipilih',
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Batal'),
                      ),
                      PopupMenuButton<BatchAction>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Aksi',
                        onSelected: (action) => switch (action) {
                          BatchAction.copy => onCopy(),
                          BatchAction.move => onMove(),
                          BatchAction.delete => onDelete(),
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: BatchAction.copy,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.copy_outlined, size: 18),
                              title: Text('Salin ke list lain'),
                            ),
                          ),
                          PopupMenuItem(
                            value: BatchAction.move,
                            enabled: canMove,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.drive_file_move_outlined,
                                size: 18,
                              ),
                              title: const Text('Pindahkan ke list lain'),
                              // Nothing to move out of when the whole
                              // collection is what's on screen.
                              subtitle: canMove ? null : moveHint,
                            ),
                          ),
                          PopupMenuItem(
                            value: BatchAction.delete,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: colors.error,
                              ),
                              title: Text(
                                'Hapus kartu terpilih',
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum BatchAction { copy, move, delete }
