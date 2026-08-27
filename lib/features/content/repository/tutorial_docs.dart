/// Ports `features/information/tutorials/docs.ts` — the tutorial index, in
/// the order the web lists it.
///
/// The bodies are the same markdown files the site serves, copied into
/// `assets/tutorials/` so the app doesn't need a round trip to read them.
class TutorialDoc {
  const TutorialDoc({
    required this.slug,
    required this.title,
    required this.description,
  });

  final String slug;
  final String title;
  final String description;

  String get asset => 'assets/tutorials/$slug.md';
}

const tutorialDocs = <TutorialDoc>[
  TutorialDoc(
    slug: 'membuat-akun',
    title: 'Membuat Akun',
    description: 'Daftar & verifikasi akun untuk mulai berjualan.',
  ),
  TutorialDoc(
    slug: 'verifikasi-nomor-hp',
    title: 'Verifikasi Nomor HP',
    description: 'Wajib sebelum bisa jual atau beli di marketplace.',
  ),
  TutorialDoc(
    slug: 'memasang-listing',
    title: 'Memasang Ask (WTS) / Listing',
    description: 'Lengkapi profil toko & pasang listing pertamamu.',
  ),
  TutorialDoc(
    slug: 'membeli-listing',
    title: 'Membeli Listing Aktif',
    description: 'Cari kartu, tambah ke keranjang, dan selesaikan pembayaran.',
  ),
  TutorialDoc(
    slug: 'mengatur-pengiriman',
    title: 'Mengatur Pengiriman (Seller)',
    description: 'Pilih pickup atau drop sendiri, cetak resi, dan kirim paket.',
  ),
  TutorialDoc(
    slug: 'menarik-penghasilan',
    title: 'Menarik Penghasilan (Withdraw)',
    description: 'Tambah rekening bank dan cairkan saldo penjualan.',
  ),
  TutorialDoc(
    slug: 'memenuhi-bid',
    title: 'Memenuhi Bid (WTB)',
    description: 'Jual langsung ke pembeli yang sudah pasang harga.',
  ),
  TutorialDoc(
    slug: 'memasang-bid',
    title: 'Memasang Bid (WTB)',
    description: 'Pasang harga beli — auto-match jika ada seller yang cocok.',
  ),
  TutorialDoc(
    slug: 'lacak-pesanan',
    title: 'Lacak Pesanan & Konfirmasi Terima',
    description:
        'Pantau status paket dan konfirmasi penerimaan sebagai pembeli.',
  ),
  TutorialDoc(
    slug: 'komplain-resolusi',
    title: 'Komplain & Pusat Resolusi',
    description: 'Ajukan klaim jika barang bermasalah — alur & batas waktu.',
  ),
  TutorialDoc(
    slug: 'kelola-koleksi',
    title: 'Kelola Koleksi',
    description: 'Catat kartu yang kamu punya dan pantau nilai portofolio.',
  ),
  TutorialDoc(
    slug: 'koleksi-vs-inventori',
    title: 'Koleksi vs Inventori',
    description: 'Perbedaan, fungsi, dan aturan sinkronisasi keduanya.',
  ),
];

/// One question and its answer out of a tutorial's `## FAQ` section.
class TutorialFaqItem {
  const TutorialFaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

class SplitTutorial {
  const SplitTutorial({required this.body, required this.faq});

  final String body;
  final List<TutorialFaqItem> faq;
}

/// Ports `splitTutorial` from `features/information/tutorials/parse.ts`:
/// drops the leading H1 (the accordion header already names the tutorial)
/// and lifts the `## FAQ` section out into its own list.
SplitTutorial splitTutorial(String markdown) {
  final withoutTitle = markdown
      .replaceFirst(RegExp(r'^# .+\n?'), '')
      .trimLeft();

  final parts = withoutTitle.split(RegExp(r'\n## FAQ\b', caseSensitive: false));
  final body = parts.first.trim();
  final faqRaw = parts.length > 1 ? parts[1] : '';

  final faq = <TutorialFaqItem>[];
  if (faqRaw.isNotEmpty) {
    // Each question opens with `### `; its answer runs to the next one.
    for (final chunk in faqRaw.split(RegExp(r'\n(?=### )'))) {
      final lines = chunk.trim().split('\n');
      if (lines.isEmpty || !lines.first.startsWith('### ')) continue;
      faq.add(
        TutorialFaqItem(
          question: lines.first.replaceFirst('### ', '').trim(),
          answer: lines.skip(1).join('\n').trim(),
        ),
      );
    }
  }

  return SplitTutorial(body: body, faq: faq);
}
