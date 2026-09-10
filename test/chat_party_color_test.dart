import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/chat/presentation/widgets/chat_party_colors.dart';

/// A person has to be the same colour in the app as on the website — the
/// bubble name and the avatar are how you tell two participants apart, and
/// two clients disagreeing about that is worse than either choice alone.
///
/// The expected indices come from running web's own `getNameColors` hash in
/// node over these ids.
void main() {
  const palette = 6;

  int indexOf(String id) {
    final colour = chatPartyColor(id);
    for (var i = 0; i < palette; i++) {
      if (chatPartyColor(_idsByIndex[i]!) == colour) return i;
    }
    return -1;
  }

  test('the hash lands where the website lands', () {
    // id -> the index node computed for it.
    const expected = {
      '3f1c2b8a-1111-4c22-9d33-aaaabbbbcccc': 2,
      'me': 0,
      'u1': 4,
      '9c2e1f40-77aa-4bb1-8c33-000111222333': 2,
      'toko-user1': 0,
    };

    for (final entry in expected.entries) {
      expect(
        indexOf(entry.key),
        entry.value,
        reason: '${entry.key} should take palette slot ${entry.value}',
      );
    }
  });

  test('the same id always gets the same colour', () {
    expect(chatPartyColor('u1'), chatPartyColor('u1'));
  });

  test('initials are the first two characters, uppercased', () {
    expect(chatInitials('Toko User1'), 'TO');
    expect(chatInitials('a'), 'A');
    expect(chatInitials('  '), '?');
  });
}

/// One id per palette slot, so a colour can be named by index without
/// exporting the palette itself.
const _idsByIndex = {0: 'f', 1: 'a', 2: 'b', 3: 'c', 4: 'd', 5: 'e'};
