import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/card_info_panel.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Real production rows: the Indonesian Beedrill (AC3a 006/205) and the
/// `get_evolution_pool` output for seeds ["Beedrill", "Kakuna"]. Pins that
/// the panel the card detail page builds renders these without throwing,
/// evolution section included.
final _cardRow = <String, dynamic>{
    "id": 20422,
    "name_id": "Beedrill",
    "expansion_code": "AC3a",
    "collector_number": "006/205",
    "rarity": "U",
    "category": "Pokemon",
    "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/AC3a/006_205.webp",
    "illustrator": "You Iribi",
    "regulation_mark": "C",
    "language": "id",
    "variant": "normal",
    "details": <String, dynamic>{
      "hp": 130,
      "attacks": [
        <String, dynamic>{
          "name": "Sengatan Takdir",
          "damage": null,
          "description": "Serangan ini hanya bisa digunakan jika Pokemon ini memiliki Token Kerusakan.",
          "energy_cost": [
            "Grass",
          ],
        },
        <String, dynamic>{
          "name": "Serangan Sembrono",
          "damage": "90",
          "description": "Pokemon ini menerima kerusakan sejumlah 10.",
          "energy_cost": [
            "Colorless",
            "Colorless",
          ],
        },
      ],
      "pokedex": <String, dynamic>{
        "height": "1",
        "number": 15,
        "weight": "29.5",
      },
      "weakness": <String, dynamic>{
        "type": "Fire",
        "modifier": "x2",
      },
      "abilities": <dynamic>[],
      "card_type": "Grass",
      "resistance": null,
      "evolves_from": "Kakuna",
      "retreat_cost": 1,
      "evolution_stage": "Stage 2",
    },
  };

final _poolRows = [
    <String, dynamic>{
      "id": 339,
      "name_id": "Beedrill",
      "expansion_code": "AR",
      "collector_number": "053/099",
      "rarity": "Common",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/AR/053_099.webp",
      "illustrator": "Wataru Kawahara",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 80,
        "attacks": [
          <String, dynamic>{
            "name": "Raid",
            "damage": "10",
            "description": "If you played Beedrill from your hand during this turn, this attack's base damage is 40 instead of 10.",
            "energy_cost": [
              "Grass",
            ],
          },
          <String, dynamic>{
            "name": "Fury Attack",
            "damage": "30x",
            "description": "Flip 3 coins. This attack does 30 damage times the number of heads.",
            "energy_cost": [
              "Grass",
              "Colorless",
              "Colorless",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "1.0",
          "number": 15,
          "weight": "29.5",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "card_type": "Grass",
        "retreat_cost": 1,
        "evolution_stage": "Basic",
      },
    },
    <String, dynamic>{
      "id": 3758,
      "name_id": "Beedrill ex",
      "expansion_code": "CRI",
      "collector_number": "003/086",
      "rarity": "Double Rare",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/CRI/003_086.webp",
      "illustrator": "toriyufu",
      "regulation_mark": "J",
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 310,
        "attacks": [
          <String, dynamic>{
            "name": "Rumbling Bees",
            "damage": "110\u00d7",
            "description": "This attack does 110 damage for each of your Beedrill and Beedrill ex in play.",
            "energy_cost": [
              "Grass",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "1.0",
          "number": 15,
          "weight": "29.5",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "card_type": "Grass",
        "evolves_from": "Kakuna",
        "retreat_cost": 1,
        "evolution_stage": "Stage 2",
      },
    },
    <String, dynamic>{
      "id": 5330,
      "name_id": "Beedrill \u03b4",
      "expansion_code": "DS",
      "collector_number": "001/113",
      "rarity": "Rare",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/DS/001_113.webp",
      "illustrator": "Masakazu Fukuda",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 90,
        "attacks": [
          <String, dynamic>{
            "name": "Super Slash",
            "damage": "50+",
            "description": "If the Defending Pok\u00e9mon is an Evolved Pok\u00e9mon, this attack does 50 damage plus 30 more damage.",
            "energy_cost": [
              "Colorless",
              "Grass",
              "Metal",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "1.0",
          "number": 15,
          "weight": "29.5",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "abilities": [
          <String, dynamic>{
            "name": "Final Sting",
            "description": "Once during your turn (before your attack), you may Knock Out Beedrill. If you do, choose 1 of your opponent's Defending Pok\u00e9mon. That Pok\u00e9mon is now Paralyzed and Poisoned. Put 2 damage counters instead of 1 on that Pok\u00e9mon between turns. This power can't be used if Beedrill is affected by a Special Condition.",
            "ability_type": "Poke-POWER",
          },
        ],
        "card_type": "Grass",
        "evolves_from": "Kakuna",
        "retreat_cost": 0,
        "evolution_stage": "Stage 2",
      },
    },
    <String, dynamic>{
      "id": 985,
      "name_id": "Kakuna",
      "expansion_code": "B2",
      "collector_number": "047/130",
      "rarity": "Uncommon",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/B2/047_130.webp",
      "illustrator": "Keiji Kinebuchi",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 80,
        "attacks": [
          <String, dynamic>{
            "name": "Stiffen",
            "description": "Flip a coin. If heads, prevent all damage done to Kakuna during your opponent's next turn. (Any other effects of attacks still happen.)",
            "energy_cost": [
              "Colorless",
              "Colorless",
            ],
          },
          <String, dynamic>{
            "name": "Poisonpowder",
            "description": "Flip a coin. If heads, the Defending Pok\u00e9mon is now Poisoned.",
            "energy_cost": [
              "Grass",
              "Grass",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "0.6",
          "number": 14,
          "weight": "10.0",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "card_type": "Grass",
        "evolves_from": "Weedle",
        "retreat_cost": 2,
        "evolution_stage": "Stage 1",
      },
    },
    <String, dynamic>{
      "id": 7295,
      "name_id": "Koga's Beedrill",
      "expansion_code": "G2",
      "collector_number": "009/132",
      "rarity": "Rare",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/G2/009_132.webp",
      "illustrator": "Ken Sugimori",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 80,
        "attacks": [
          <String, dynamic>{
            "name": "Nerve Poison",
            "damage": "20",
            "description": "Flip a coin. If heads, the Defending Pok\u00e9mon is now Paralyzed and Poisoned.",
            "energy_cost": [
              "Grass",
              "Grass",
            ],
          },
          <String, dynamic>{
            "name": "Hyper Needle",
            "description": "Flip a coin. If tails, this attack does nothing. Either way, you can't use this attack again as long as Koga's Beedrill stays in play (even putting Koga's Beedrill on the Bench won't let you use it again).",
            "energy_cost": [
              "Colorless",
              "Colorless",
              "Colorless",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "1.0",
          "number": 15,
          "weight": "29.5",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "card_type": "Grass",
        "resistance": <String, dynamic>{
          "type": "Fighting",
          "modifier": "-30",
        },
        "evolves_from": "Kakuna",
        "evolution_stage": "Stage 2",
      },
    },
    <String, dynamic>{
      "id": 7333,
      "name_id": "Koga's Kakuna",
      "expansion_code": "G2",
      "collector_number": "047/132",
      "rarity": "Uncommon",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/G2/047_132.webp",
      "illustrator": "Ken Sugimori",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 60,
        "attacks": [
          <String, dynamic>{
            "name": "Toxic Secretion",
            "description": "Flip a coin. If heads, the Defending Pok\u00e9mon is now Poisoned. It takes 20 Poison damage instead of 10 after each player's turn (even if it was already Poisoned).",
            "energy_cost": [
              "Grass",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "0.6",
          "number": 14,
          "weight": "10.0",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "abilities": [
          <String, dynamic>{
            "name": "Emerge",
            "description": "Once during your turn (before your attack), you may flip a coin. If heads, search your deck for an Evolution card named Koga's Beedrill and put it on Koga's Kakuna. (This counts as evolving Koga's Kakuna.) Shuffle your deck afterward. This power can't be used if Koga's Kakuna is Asleep, Confused, or Paralyzed.",
            "ability_type": "Poke-POWER",
          },
        ],
        "card_type": "Grass",
        "evolves_from": "Weedle",
        "retreat_cost": 2,
        "evolution_stage": "Stage 1",
      },
    },
    <String, dynamic>{
      "id": 1038,
      "name_id": "Weedle",
      "expansion_code": "B2",
      "collector_number": "100/130",
      "rarity": "Common",
      "category": "Pokemon",
      "image_url": "https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev/en/B2/100_130.webp",
      "illustrator": "Mitsuhiro Arita",
      "regulation_mark": null,
      "language": "en",
      "variant": "normal",
      "details": <String, dynamic>{
        "hp": 40,
        "attacks": [
          <String, dynamic>{
            "name": "Poison Sting",
            "damage": "10",
            "description": "Flip a coin. If heads, Defending Pok\u00e9mon is now Poisoned.",
            "energy_cost": [
              "Grass",
            ],
          },
        ],
        "pokedex": <String, dynamic>{
          "height": "0.3",
          "number": 13,
          "weight": "3.2",
        },
        "weakness": <String, dynamic>{
          "type": "Fire",
          "modifier": "\u00d72",
        },
        "card_type": "Grass",
        "retreat_cost": 1,
        "evolution_stage": "Basic",
      },
    },
  ];

void main() {
  testWidgets('CardInfoPanel renders a real card inside a ListView', (tester) async {
    final card = CardModel.fromRow(_cardRow);
    final pool = _poolRows.map(CardModel.fromRow).toList();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          evolutionPoolProvider((
            name: card.name,
            evolvesFrom: card.details.evolvesFrom,
          )).overrideWith((ref) async => pool),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [CardInfoPanel(card: card)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Evolusi'), findsOneWidget);
    expect(find.text('Weedle'), findsOneWidget);
    expect(find.text('Kakuna'), findsOneWidget);
  });
}
