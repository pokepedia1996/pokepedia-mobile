// Indonesian mobile numbers, as Buka Toko's phone step types and shows
// them. The server's `normalizeIndonesianPhone` stays the authority on what
// it accepts; these only shape what is on screen.

/// The digits after +62 — "8123456789" — from however it was typed: with
/// +62, 62 or 0 in front, with spaces or dashes. Empty when nothing usable
/// is there.
String idPhoneLocalDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('62')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

/// Whether [localDigits] makes a mobile number the server would take:
/// `^\+?62\d{9,12}$`, and a mobile one, so starting with 8.
bool isIdMobileLocal(String localDigits) =>
    RegExp(r'^8\d{8,11}$').hasMatch(localDigits);

/// "812 3456 7890": the local digits grouped as Indonesians read them.
String groupIdLocal(String localDigits) {
  final d = localDigits;
  if (d.length <= 3) return d;
  if (d.length <= 7) return '${d.substring(0, 3)} ${d.substring(3)}';
  return '${d.substring(0, 3)} ${d.substring(3, 7)} ${d.substring(7)}';
}

/// "0812 3456 7890" — a stored `+62…` number, as it is said aloud.
String formatIdPhone(String phone) {
  final local = idPhoneLocalDigits(phone);
  if (local.isEmpty) return phone;
  return '0${groupIdLocal(local)}';
}

/// "0812 •••• 4417" — enough to recognise the number, not to copy it.
String maskIdPhone(String phone) {
  final full = '0${idPhoneLocalDigits(phone)}';
  if (full.length < 8) return full;
  return '${full.substring(0, 4)} •••• ${full.substring(full.length - 4)}';
}
