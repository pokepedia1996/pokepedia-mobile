import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

const maxDeckNameLen = 100;
const maxDeckDescLen = 500;

/// Name + description bottom sheet, used for creating and editing a deck
/// (`DeckTab`, `DeckDetailPage`) and a list (`ListsPage`) alike — the two
/// forms are the same shape and the same length limits.
class DeckFormSheet extends StatefulWidget {
  const DeckFormSheet({
    super.key,
    required this.title,
    required this.submitLabel,
    this.nameLabel = 'Nama deck',
    this.initialName = '',
    this.initialDescription = '',
  });

  final String title;
  final String submitLabel;

  /// What the name field is called — a deck by default, a list when the
  /// lists page opens it.
  final String nameLabel;
  final String initialName;
  final String initialDescription;

  @override
  State<DeckFormSheet> createState() => _DeckFormSheetState();
}

class _DeckFormSheetState extends State<DeckFormSheet> {
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _descController = TextEditingController(text: widget.initialDescription);

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppTypography.h3(context.appColors.onSurface)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: maxDeckNameLen,
            decoration: InputDecoration(labelText: widget.nameLabel),
          ),
          TextField(
            controller: _descController,
            maxLength: maxDeckDescLen,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Deskripsi (opsional)'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: _nameController,
            builder: (context, value, _) => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(context).pop((
                        name: value.text.trim(),
                        description: _descController.text.trim(),
                      )),
                child: Text(widget.submitLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
