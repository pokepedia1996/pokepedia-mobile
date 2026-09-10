import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The six colours web assigns a chat participant, in `NAME_COLORS` order.
///
/// A conversation's names have to be told apart at a glance, and the same
/// person must keep the same colour across sessions and across both clients
/// — so the colour is derived from the user id rather than from where they
/// happen to sit in the list.
class ChatPartyColor {
  const ChatPartyColor({required this.text, required this.avatar});

  /// The sender's name inside the bubble.
  final Color text;

  /// The circle their initials sit on.
  final Color avatar;
}

const _palette = [
  ChatPartyColor(text: AppColors.blue70, avatar: AppColors.blue60),
  ChatPartyColor(text: AppColors.green70, avatar: AppColors.green60),
  ChatPartyColor(text: Color(0xFF9333EA), avatar: Color(0xFFA855F7)),
  ChatPartyColor(text: Color(0xFFEA580C), avatar: Color(0xFFF97316)),
  ChatPartyColor(text: Color(0xFFDB2777), avatar: Color(0xFFEC4899)),
  ChatPartyColor(text: Color(0xFF0D9488), avatar: Color(0xFF14B8A6)),
];

/// Ports web's `getNameColors` — the same string hash over the user id, so a
/// person is the same colour in the app as on the site.
ChatPartyColor chatPartyColor(String userId) {
  var hash = 0;
  for (var i = 0; i < userId.length; i++) {
    // `hash = charCodeAt(i) + ((hash << 5) - hash)`, with JS's semantics
    // spelled out: only the shift is truncated to 32 bits there (`<<`
    // coerces), while the surrounding arithmetic stays wide. Truncating the
    // whole expression instead — the obvious Dart port — lands on a
    // different colour than the website gives the same person.
    final shifted = (hash.toSigned(32) << 5).toSigned(32);
    hash = userId.codeUnitAt(i) + shifted - hash;
  }
  return _palette[hash.abs() % _palette.length];
}

/// Two-letter initials, as web takes them: the first two characters of the
/// name, uppercased.
String chatInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, trimmed.length < 2 ? 1 : 2).toUpperCase();
}
