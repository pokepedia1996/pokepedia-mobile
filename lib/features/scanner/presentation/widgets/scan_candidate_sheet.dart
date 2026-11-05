import 'package:flutter/material.dart';

import '../../repository/models/scan_models.dart';
import 'scan_card_thumb.dart';

/// An uncertain result is a suggestion, never an automatic session addition.
class ScanCandidateSheet extends StatelessWidget {
  const ScanCandidateSheet({
    super.key,
    required this.candidates,
    required this.onSelect,
    required this.onSearch,
  });

  final List<ScanCard> candidates;
  final ValueChanged<ScanCard> onSelect;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Kartu mana yang sesuai?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Hasil belum pasti. Pilih sebelum ditambahkan.'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final card = candidates[index];
                return ListTile(
                  leading: SizedBox(
                    width: 42,
                    height: 58,
                    child: ScanCardThumb(card: card),
                  ),
                  title: Text(card.displayName),
                  subtitle: Text(card.printingLabel),
                  onTap: () => onSelect(card),
                );
              },
            ),
          ),
          TextButton(onPressed: onSearch, child: const Text('Cari kartu lain')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Lewati'),
          ),
        ],
      ),
    ),
  );
}
