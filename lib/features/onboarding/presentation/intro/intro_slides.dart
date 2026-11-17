/// One intro slide: the handwritten line over the heading, the two-line
/// heading (the second line in red), the sub, and the drawing in
/// `onboarding_scribble.json` it plays.
class IntroSlide {
  const IntroSlide({
    required this.eyebrow,
    required this.first,
    required this.second,
    required this.sub,
    required this.drawing,
    required this.cta,
  });

  final String eyebrow;
  final String first;
  final String second;
  final String sub;
  final String drawing;
  final String cta;
}

/// Slides 0–5. Slide 6 (Daftar) has its own layout in `intro_page.dart`.
const introSlides = <IntroSlide>[
  IntroSlide(
    eyebrow: 'selamat datang!',
    first: 'Halo,',
    second: 'kolektor!',
    sub:
        'Pokepedia tempat catat koleksi, cek harga, dan jual-beli kartu TCG di Indonesia.',
    drawing: 'intro_welcome',
    cta: 'Kenalan dulu, yuk',
  ),
  IntroSlide(
    eyebrow: 'fitur 1 dari 5',
    first: 'Scan kartu,',
    second: 'tahu nilainya',
    sub:
        'Arahkan kamera ke kartu. Langsung masuk portofolio, lengkap dengan harga pasarnya.',
    drawing: 'intro_scan',
    cta: 'Lanjut',
  ),
  IntroSlide(
    eyebrow: 'fitur 2 dari 5',
    first: 'Pantau',
    second: 'harga pasar',
    sub:
        'Histori harga kartu Indonesia, Jepang, Inggris, sampai barang sealed.',
    drawing: 'intro_pasar',
    cta: 'Lanjut',
  ),
  IntroSlide(
    eyebrow: 'fitur 3 dari 5',
    first: 'Rakit deck,',
    second: 'siap tanding',
    sub:
        'Susun 60 kartu dan cek aturan main otomatis. Daftar deck bisa dibagikan lewat link.',
    drawing: 'intro_deck',
    cta: 'Lanjut',
  ),
  IntroSlide(
    eyebrow: 'fitur 4 dari 5',
    first: 'Jual, beli,',
    second: 'atau tawar',
    sub:
        'Pasang WTS buat jual, WTB buat cari kartu incaran, atau ajukan bid sesuai budget.',
    drawing: 'intro_jualbeli',
    cta: 'Lanjut',
  ),
  IntroSlide(
    eyebrow: 'fitur 5 dari 5',
    first: 'Uang aman sampai',
    second: 'kartu diterima',
    sub:
        'Pembayaran ditahan Pokepedia sampai paketmu tiba. Resi bisa dilacak dari app.',
    drawing: 'intro_aman',
    cta: 'Mulai sekarang',
  ),
];

/// The Daftar screen's copy (slide 6).
const introSignup = IntroSlide(
  eyebrow: 'satu langkah lagi',
  first: 'Bikin akun, yuk!',
  second: '',
  sub:
      'Gratis, cuma butuh semenit. Koleksi dan transaksimu tersimpan aman di akunmu.',
  drawing: 'intro_daftar',
  cta: '',
);
