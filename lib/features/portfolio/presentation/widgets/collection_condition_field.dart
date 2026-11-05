import 'package:flutter/material.dart';

import '../../../../shared/models/card_condition.dart';
import '../../../../shared/widgets/condition_badge.dart';

/// The condition a collection's copies are filed under — a dropdown of the
/// raw grades plus DMG that `collection_cards_condition_check` allows.
///
/// Raw only: slabs aren't tracked in a collection yet, so the graded grades
/// listings take aren't offered here.
class CollectionConditionField extends StatelessWidget {
  const CollectionConditionField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.counts,
  });

  final CardCondition value;

  /// Null disables the field, as while a write is in flight.
  final ValueChanged<CardCondition>? onChanged;

  /// "Kondisi" above the field. Left out where the row already says it.
  final String? label;

  /// Copies held in each condition, shown beside the ones that have any so
  /// the reader can see what else the card sits in before switching.
  final Map<CardCondition, int>? counts;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<CardCondition>(
      // Keyed by the value: a form field only reads `initialValue` once, and
      // the parent can move it (switching portfolio re-seeds it).
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      // The closed field keeps to the code, which is all a narrow row fits;
      // the menu has room to spell the grade out.
      selectedItemBuilder: (context) => [
        for (final condition in collectionConditions)
          Align(
            alignment: Alignment.centerLeft,
            child: ConditionBadge(condition: condition, colored: true),
          ),
      ],
      items: [
        for (final condition in collectionConditions)
          DropdownMenuItem(
            value: condition,
            child: Row(
              children: [
                ConditionBadge(condition: condition, colored: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(condition.label, overflow: TextOverflow.ellipsis),
                ),
                if ((counts?[condition] ?? 0) > 0)
                  Text('×${counts![condition]}'),
              ],
            ),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (condition) {
              if (condition != null) onChanged!(condition);
            },
    );
  }
}
