import '../../../../shared/widgets/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../repository/models/scan_models.dart';
import '../../repository/scanner_repository.dart';
import 'scan_card_thumb.dart';

/// Ports `ScanCardSearchSheet` — the full-catalog escape hatch behind the
/// variant strip's search tile, for when recognition missed the card entirely
/// rather than just picking the wrong printing.
///
/// Scoped to one language on purpose: the scan-screen toggle is authoritative
/// for print language, so a correction here must not be able to silently
/// reassign the card to a different language than the batch was tagged with.
class ScanCardSearchSheet extends ConsumerStatefulWidget {
  const ScanCardSearchSheet({
    super.key,
    required this.language,
    required this.onSelect,
  });

  final CardLanguage? language;
  final ValueChanged<ScanCard> onSelect;

  @override
  ConsumerState<ScanCardSearchSheet> createState() =>
      _ScanCardSearchSheetState();
}

class _ScanCardSearchSheetState extends ConsumerState<ScanCardSearchSheet> {
  /// Long enough that typing a card name doesn't fire a query per keystroke,
  /// short enough not to feel laggy.
  static const _debounce = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _debounceTimer;
  var _loading = false;
  List<ScanCard> _results = const [];

  /// Guards against an earlier, slower query landing after a later one and
  /// showing results for a prefix the user has already typed past.
  var _generation = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounceTimer = Timer(_debounce, () => _search(value));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    final cards = await ref
        .read(scannerRepositoryProvider)
        .searchCards(query: query, language: widget.language);
    if (!mounted || generation != _generation) return;
    setState(() {
      _results = cards;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppSearchField(
              hintText: 'Cari kartu…',
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
            ),
          ),
          Expanded(child: _buildBody(scrollController)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _controller.text.trim().isEmpty
              ? 'Ketik nama kartu untuk mencari'
              : 'Kartu tidak ditemukan',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final card = _results[index];
        return ListTile(
          leading: ScanCardThumb(card: card, width: 36),
          title: Text(
            card.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
          subtitle: Text(
            [
              card.printingLabel,
              if (card.variantLabel != null) card.variantLabel!,
            ].join(' · '),
            style: AppTypography.caption(context.mutedForeground),
          ),
          onTap: () => widget.onSelect(card),
        );
      },
    );
  }
}
