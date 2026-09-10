import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

const _maxNoteLength = 200;

/// Ports `features/checkout/ui/BuyerNoteBox.tsx` — an optional note to the
/// seller shown while processing the order.
class BuyerNoteBox extends StatefulWidget {
  const BuyerNoteBox({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<BuyerNoteBox> createState() => _BuyerNoteBoxState();
}

class _BuyerNoteBoxState extends State<BuyerNoteBox> {
  late final _controller = TextEditingController(text: widget.value);
  late int _length = widget.value.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Kasih Catatan',
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
              ),
              Text(
                '$_length/$_maxNoteLength',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLength: _maxNoteLength,
            maxLines: 3,
            onChanged: (v) {
              setState(() => _length = v.length);
              widget.onChanged(v);
            },
            style: AppTypography.bodySm(colors.onSurface),
            decoration: InputDecoration(
              hintText:
                  'Contoh: Mohon dikemas dengan bubble wrap, kartu fragile.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Opsional. Catatan ini akan dilihat penjual saat memproses pesanan.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}
