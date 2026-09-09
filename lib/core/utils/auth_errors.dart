/// Translates Supabase Auth error messages into the same Indonesian copy
/// `pokepedia-web` shows, mirroring `lib/utils/index.tsx` and the inline
/// mappings in `app/login/page.tsx` / `app/signup/page.tsx`.
/// [provider] names the social provider a failure came from, so the
/// disabled-provider message can say which one. It used to be hardcoded to
/// "Google", which told an Apple user the wrong thing entirely.
String translateAuthError(String raw, {String? provider}) {
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
  // Supabase answers an OAuth attempt for a provider that isn't turned on
  // in the project with this. It's a configuration gap, not the user's
  // mistake, so say so rather than showing the raw string.
  if (raw.contains('provider is not enabled') ||
      raw.contains('Unsupported provider')) {
    final name = provider == null ? '' : ' dengan $provider';
    return 'Login$name belum tersedia. Coba masuk dengan email.';
  }
  // Apple's own failures arrive as opaque codes. `1000` is the one a
  // misconfigured build hits: the Sign in with Apple capability isn't on the
  // App ID, or the device has no iCloud account signed in.
  if (raw.contains('AuthorizationErrorCode.unknown') ||
      raw.contains('error 1000') ||
      raw.contains('com.apple.AuthenticationServices')) {
    return 'Masuk dengan Apple belum bisa dipakai di perangkat ini. '
        'Pastikan kamu sudah masuk ke iCloud, lalu coba lagi.';
  }
  if (raw.contains('AuthorizationErrorCode.notHandled') ||
      raw.contains('AuthorizationErrorCode.failed')) {
    return 'Apple menolak permintaan masuk. Coba lagi sebentar lagi.';
  }
  if (raw.contains('AuthorizationErrorCode.invalidResponse')) {
    return 'Balasan dari Apple tidak valid. Coba lagi.';
  }
  if (raw.contains('Failed to fetch') || raw.contains('SocketException')) {
    return 'Koneksi gagal. Periksa koneksi internet atau coba lagi.';
  }
  return raw;
}
