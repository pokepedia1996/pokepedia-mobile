/// Translates Supabase Auth error messages into the same Indonesian copy
/// `pokepedia-web` shows, mirroring `lib/utils/index.tsx` and the inline
/// mappings in `app/login/page.tsx` / `app/signup/page.tsx`.
String translateAuthError(String raw) {
  if (raw.contains('Invalid login credentials')) {
    return 'Email atau password salah';
  }
  if (raw.contains('email rate limit exceeded')) {
    return 'Terlalu banyak percobaan. Coba lagi dalam beberapa menit.';
  }
  if (raw.contains('Password should contain at least one character of each')) {
    return 'Password harus mengandung huruf besar, huruf kecil, angka, dan karakter spesial';
  }
  if (raw.contains('should be different from the old password')) {
    return 'Password baru harus berbeda dari password lama';
  }
  if (raw.contains('Failed to fetch') || raw.contains('SocketException')) {
    return 'Koneksi gagal. Periksa koneksi internet atau coba lagi.';
  }
  return raw;
}
