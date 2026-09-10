import '../../../../shared/models/card_model.dart';

enum DeckCategory { pokemon, trainer, energy }

extension DeckCategoryX on DeckCategory {
  String get label {
    switch (this) {
      case DeckCategory.pokemon:
        return 'Pokemon';
      case DeckCategory.trainer:
        return 'Trainer';
      case DeckCategory.energy:
        return 'Energy';
    }
  }
}

class DeckCardEntry {
  const DeckCardEntry({
    required this.card,
    required this.quantity,
    required this.category,
  });

  final CardModel card;
  final int quantity;
  final DeckCategory category;
}
