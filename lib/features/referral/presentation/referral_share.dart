import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/utils/csv_export.dart' show shareOriginOf;
import '../../../shared/utils/social_share.dart';
import '../repository/models/referral_models.dart';
import 'referral_style.dart';

/// Per code (so per user): a message saved by one account must not be sent
/// by the next account signed in on the same phone.
String _messageKey(ReferralDashboard d) => 'referral.share_message.${d.code}';

String referralDefaultMessage(ReferralDashboard d) =>
    'Halo! Aku pakai Pokepedia buat jual-beli kartu TCG. Daftar pakai kode '
    '${d.code} ya, kamu langsung dapat kupon gratis ongkir s/d '
    '${formatRupiah(d.couponMaxAmount)} buat belanja kartu pertama.\n${d.link}';

/// An edited message must still carry the code and link (02 §3).
String ensureCodeAndLink(String message, ReferralDashboard d) {
  var m = message.trim();
  if (d.code != null && !m.contains(d.code!)) m = '$m\nKode: ${d.code}';
  if (d.link != null && !m.contains(d.link!)) m = '$m\n${d.link}';
  return m;
}

Future<String> loadReferralMessage(ReferralDashboard d) async {
  try {
    final saved = (await SharedPreferences.getInstance()).getString(
      _messageKey(d),
    );
    if (saved != null && saved.trim().isNotEmpty) {
      return ensureCodeAndLink(saved, d);
    }
  } catch (_) {}
  return referralDefaultMessage(d);
}

/// False when the edit couldn't be stored, so the sheet can say so.
Future<bool> _saveMessage(ReferralDashboard d, String message) async {
  try {
    await (await SharedPreferences.getInstance()).setString(
      _messageKey(d),
      message,
    );
    return true;
  } catch (e) {
    debugPrint('[referral] saving the share message failed: $e');
    return false;
  }
}

/// The capture can't take this long unless something is stuck (a font or an
/// asset that never resolves); past it the share fails visibly instead of
/// leaving every button dead.
const _renderTimeout = Duration(seconds: 20);

/// Renders [image] off-screen at [size] logical px into a PNG at 3x (1080 px
/// wide). Uses an overlay so nothing flashes on screen. Throws when the
/// capture fails, so the caller's guard can tell the user.
Future<File> renderReferralImage(
  BuildContext context, {
  required Widget image,
  required Size size,
  required String fileName,
}) => _render(context, image, size, fileName).timeout(_renderTimeout);

Future<File> _render(
  BuildContext context,
  Widget image,
  Size size,
  String fileName,
) async {
  // Request every face the images use, then wait, so the capture isn't
  // drawn in a fallback font.
  handStyle(Colors.black);
  for (final w in const [FontWeight.w400, FontWeight.w700]) {
    GoogleFonts.urbanist(fontWeight: w);
  }
  await GoogleFonts.pendingFonts().timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      debugPrint('[referral] fonts not loaded in 5 s; capturing anyway');
      return const [];
    },
  );
  if (!context.mounted) throw StateError('share cancelled: context gone');
  // precacheImage reports a failed asset instead of throwing, which would
  // send a picture with a hole in it.
  Object? assetError;
  for (final asset in _shareAssets) {
    await precacheImage(
      AssetImage(asset),
      context,
      onError: (e, _) => assetError ??= '$asset: $e',
    );
  }
  if (assetError != null) {
    throw StateError('share image asset failed: $assetError');
  }
  if (!context.mounted) throw StateError('share cancelled: context gone');

  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -size.width * 4,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            // Without a Material the overlay inherits MaterialApp's yellow
            // double-underline "missing Material" text style.
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox.fromSize(size: size, child: image),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  ByteData? data;
  try {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('share image was not laid out');
    final shot = await boundary.toImage(pixelRatio: 3);
    try {
      data = await shot.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      shot.dispose();
    }
  } finally {
    // Gone before the share sheet opens, not held for as long as it is up.
    entry.remove();
  }
  if (data == null) throw StateError('share image could not be encoded');
  // Its own folder: the only one the Android FileProvider exposes to
  // Instagram / WhatsApp, rather than the whole cache.
  final dir = Directory('${(await getTemporaryDirectory()).path}/social_share');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$fileName.png');
  await file.writeAsBytes(data.buffer.asUint8List());
  return file;
}

/// The system share sheet with [file] and [text]. [origin] anchors the
/// popover on iPad, which refuses to share without one.
Future<void> _shareSheet(File file, String? text, Rect? origin) =>
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: text,
        sharePositionOrigin: origin,
      ),
    );

/// The system share sheet with the image and message together.
Future<void> shareReferralImage(
  BuildContext context, {
  required Widget image,
  required Size size,
  required String fileName,
  String? text,
}) async {
  final origin = shareOriginOf(context);
  final file = await renderReferralImage(
    context,
    image: image,
    size: size,
    fileName: fileName,
  );
  await _shareSheet(file, text, origin);
}

/// Straight into Instagram's Story editor with the story image as the
/// background. Stories take no caption, so the message isn't sent. Falls back
/// to the share sheet when Instagram (or the Meta App ID) is missing.
Future<void> shareReferralToInstagramStory(
  BuildContext context, {
  required ReferralDashboard dashboard,
  required String username,
  required String text,
}) async {
  final origin = shareOriginOf(context);
  final file = await renderReferralImage(
    context,
    image: ReferralStoryImage(dashboard: dashboard, username: username),
    size: const Size(360, 640),
    fileName: 'pokepedia-ajak-teman-story',
  );
  if (await SocialShare.instagramStory(file.path)) return;
  await _shareSheet(file, text, origin);
}

/// WhatsApp with the square image and the message. Android goes straight to
/// WhatsApp (or WhatsApp Business); iOS can only do image plus text through
/// the share sheet, where the user picks WhatsApp. Either way the image is
/// never dropped: anything that can't go direct goes to the share sheet.
Future<void> shareReferralToWhatsApp(
  BuildContext context, {
  required ReferralDashboard dashboard,
  required String username,
  required String text,
}) async {
  final origin = shareOriginOf(context);
  final file = await renderReferralImage(
    context,
    image: ReferralSquareImage(dashboard: dashboard, username: username),
    size: const Size(360, 360),
    fileName: 'pokepedia-ajak-teman',
  );
  if (await SocialShare.whatsapp(file.path, text)) return;
  await _shareSheet(file, text, origin);
}

const _shareAssets = [
  '$referralImageDir/pattern-energi-tile-krem.webp',
  '$referralImageDir/kupon-coretan.webp',
  '$referralImageDir/card-back.webp',
  '$referralImageDir/badge-app-store.webp',
  '$referralImageDir/badge-google-play.webp',
  'assets/images/horizontal-logo-light.webp',
];

class ReferralCodeBox extends StatelessWidget {
  const ReferralCodeBox({super.key, required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: ReferralColors.codeBg,
        border: Border.all(color: ReferralColors.codeLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            // Shrinks rather than wrapping a long code mid-code.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                code,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'CalSans',
                  fontSize: 28,
                  letterSpacing: 1,
                  color: ReferralColors.ink,
                ),
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ReferralColors.ink,
              shape: const StadiumBorder(
                side: BorderSide(color: ReferralColors.codeLine),
              ),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onCopy,
            icon: const Icon(LucideIcons.copy, size: 14),
            label: const Text('Salin'),
          ),
        ],
      ),
    );
  }
}

/// Label of the button whose image is being made, so that one shows a
/// spinner and a second tap is ignored. Null when idle.
final _busy = ValueNotifier<String?>(null);

Widget _instagramIcon(Color color) => SvgPicture.asset(
  'assets/images/social/instagram.svg',
  width: 20,
  height: 20,
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
);

/// WhatsApp · Instagram · Salin link · Lainnya (02 §2.2).

class ReferralQuickShare extends StatelessWidget {
  const ReferralQuickShare({
    super.key,
    required this.dashboard,
    required this.username,
    this.copyMessage = false,
    this.message,
    this.onNotice,
  });

  /// Shows a short notice. Inside the share sheet a SnackBar would land on
  /// the page behind it, out of sight, so the sheet shows its own.
  final ValueChanged<String>? onNotice;

  final ReferralDashboard dashboard;
  final String username;

  /// Third button copies the whole message (sheet) instead of the link.
  final bool copyMessage;

  /// Message to send; the saved/default one when null.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    Future<String> msg() async => message ?? await loadReferralMessage(d);
    void toast(String m) {
      if (!context.mounted) return;
      if (onNotice case final notice?) return notice(m);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(m), persist: false));
    }

    // One share at a time: a double tap opened two capture + share sheets.
    Future<void> guard(String label, Future<void> Function() run) async {
      if (_busy.value != null) return;
      _busy.value = label;
      try {
        await run();
      } catch (e, st) {
        debugPrint('[referral] share failed: $e\n$st');
        toast('Gagal membagikan. Coba lagi.');
      } finally {
        _busy.value = null;
      }
    }

    Widget lucide(IconData icon, Color color) =>
        Icon(icon, size: 20, color: color);

    final igLabel = copyMessage ? 'IG Story' : 'Instagram';
    final items = <(Widget Function(Color), String, Color, VoidCallback)>[
      (
        (c) => lucide(LucideIcons.messageCircle, c),
        'WhatsApp',
        const Color(0xFF128C7E),
        () => guard('WhatsApp', () async {
          final text = await msg();
          if (!context.mounted) return;
          await shareReferralToWhatsApp(
            context,
            dashboard: d,
            username: username,
            text: text,
          );
        }),
      ),
      (
        _instagramIcon,
        igLabel,
        const Color(0xFFE1306C),
        () => guard(igLabel, () async {
          final text = await msg();
          if (!context.mounted) return;
          await shareReferralToInstagramStory(
            context,
            dashboard: d,
            username: username,
            text: text,
          );
        }),
      ),
      copyMessage
          ? (
              (c) => lucide(LucideIcons.copy, c),
              'Salin pesan',
              context.appColors.onSurface,
              () => guard('Salin pesan', () async {
                await Clipboard.setData(ClipboardData(text: await msg()));
                toast('Pesan disalin');
              }),
            )
          : (
              (c) => lucide(LucideIcons.link, c),
              'Salin link',
              context.appColors.onSurface,
              () => guard('Salin link', () async {
                final link = d.link;
                if (link == null) {
                  toast('Link belum tersedia');
                  return;
                }
                await Clipboard.setData(ClipboardData(text: link));
                toast('Link disalin');
              }),
            ),
      (
        (c) => lucide(LucideIcons.ellipsis, c),
        'Lainnya',
        context.mutedForeground,
        () => guard('Lainnya', () async {
          final text = await msg();
          if (!context.mounted) return;
          await shareReferralImage(
            context,
            image: ReferralSquareImage(dashboard: d, username: username),
            size: const Size(360, 360),
            fileName: 'pokepedia-ajak-teman',
            text: text,
          );
        }),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (final (icon, label, color, onTap) in items)
          ValueListenableBuilder<String?>(
            valueListenable: _busy,
            builder: (_, busy, __) {
              final working = busy == label;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: working
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: color,
                                ),
                              )
                            : icon(color),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        working ? 'Menyiapkan…' : label,
                        style: AppTypography.caption(
                          context.appColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

Future<void> showReferralShareSheet(BuildContext context, ReferralDashboard d) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ShareSheet(dashboard: d),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.dashboard});

  final ReferralDashboard dashboard;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _controller = TextEditingController();
  var _editing = false;

  /// A short confirmation shown inside the sheet; a SnackBar would sit on
  /// the page behind it.
  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String message) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void initState() {
    super.initState();
    loadReferralMessage(widget.dashboard).then((m) {
      if (mounted) setState(() => _controller.text = m);
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    if (_editing) {
      final fixed = ensureCodeAndLink(_controller.text, widget.dashboard);
      _controller.text = fixed;
      _saveMessage(widget.dashboard, fixed).then((saved) {
        if (!saved) _showNotice('Pesan tidak tersimpan untuk lain kali');
      });
    }
    setState(() => _editing = !_editing);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dashboard;
    final colors = context.appColors;
    final muted = context.mutedForeground;
    final username = ref.watch(authProvider).valueOrNull?.username ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.mutedForeground.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bagikan kupon ke teman',
              style: AppTypography.h3(colors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Temanmu dapat kupon gratis ongkir s/d ${formatRupiah(d.couponMaxAmount)}. '
              'Setelah belanja pertamanya selesai (min. Rp30rb), kamu dapat 1 Pack Hadiah.',
              style: AppTypography.bodySm(muted),
            ),
            const SizedBox(height: 16),
            Text(
              'YANG DITERIMA TEMANMU',
              style: GoogleFonts.urbanist(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: muted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F8DD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 200,
                      // A picture of what gets sent: kept out of the screen
                      // reader (the code box below says the same) and laid
                      // out unscaled, like the exported image.
                      child: ExcludeSemantics(
                        child: MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: TextScaler.noScaling),
                          child: FittedBox(
                            child: SizedBox(
                              width: 360,
                              height: 640,
                              child: ReferralStoryImage(
                                dashboard: d,
                                username: username,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _editing
                      ? TextField(
                          controller: _controller,
                          maxLines: null,
                          style: AppTypography.bodySm(ReferralColors.ink),
                          // No theme fill: in dark it painted a near-black
                          // box with near-black text inside the light bubble.
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                          ),
                        )
                      : Text(
                          _controller.text,
                          style: AppTypography.bodySm(ReferralColors.ink),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    'pokepedia.id',
                    style: AppTypography.caption(ReferralColors.muted),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _toggleEdit,
                icon: Icon(
                  _editing ? LucideIcons.check : LucideIcons.pencil,
                  size: 14,
                ),
                label: Text(_editing ? 'Simpan pesan' : 'Ubah pesan'),
              ),
            ),
            if (d.code != null)
              ReferralCodeBox(
                code: d.code!,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: d.code!));
                  _showNotice('Kode disalin');
                },
              ),
            const SizedBox(height: 16),
            // Rebuilt as the user types, so a share mid-edit sends what is
            // on screen rather than the text from before the edit.
            ListenableBuilder(
              listenable: _controller,
              builder: (_, __) => ReferralQuickShare(
                dashboard: d,
                username: username,
                copyMessage: true,
                message: _controller.text.isEmpty
                    ? null
                    : ensureCodeAndLink(_controller.text, d),
                onNotice: _showNotice,
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: _notice == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _notice!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration get _creamBg => const BoxDecoration(
  color: ReferralColors.cream,
  image: DecorationImage(
    image: AssetImage('$referralImageDir/pattern-energi-tile-krem.webp'),
    repeat: ImageRepeat.repeat,
    scale: 2,
  ),
);

Widget _invitePill(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(999),
  ),
  child: Text(
    text,
    style: GoogleFonts.urbanist(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: ReferralColors.ink,
    ),
  ),
);

Widget _hardShadowCard({required Widget child, EdgeInsets? padding}) =>
    Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReferralColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: ReferralColors.ink, offset: Offset(3, 3)),
        ],
      ),
      child: child,
    );

/// 1080×1920 story image (02 §4), laid out at 360×640.
class ReferralStoryImage extends StatelessWidget {
  const ReferralStoryImage({
    super.key,
    required this.dashboard,
    required this.username,
  });

  final ReferralDashboard dashboard;
  final String username;

  @override
  Widget build(BuildContext context) {
    final code = dashboard.code ?? '';
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: ReferralColors.red,
            child: Text(
              '$n',
              style: GoogleFonts.urbanist(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.urbanist(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ReferralColors.ink,
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: _creamBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Image.asset('assets/images/horizontal-logo-light.webp', height: 28),
            const SizedBox(height: 14),
            if (username.isNotEmpty)
              _invitePill('@$username ngajak kamu ke Pokepedia'),
            const SizedBox(height: 12),
            Text(
              'Gratis ongkir buat kartu pertamamu!',
              textAlign: TextAlign.center,
              style: handStyle(ReferralColors.ink, size: 42),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                    angle: -0.18,
                    child: Image.asset(
                      '$referralImageDir/card-back.webp',
                      height: 140,
                    ),
                  ),
                  Transform.rotate(
                    angle: 0.16,
                    child: Image.asset(
                      '$referralImageDir/card-back.webp',
                      height: 140,
                    ),
                  ),
                  Transform.rotate(
                    angle: -0.05,
                    child: Image.asset(
                      '$referralImageDir/kupon-coretan.webp',
                      width: 230,
                    ),
                  ),
                ],
              ),
            ),
            _hardShadowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Isi kode ini waktu daftar di Pokepedia',
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ReferralColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: ReferralColors.codeBg,
                      border: Border.all(color: ReferralColors.red, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      code,
                      textAlign: TextAlign.center,
                      style: handStyle(ReferralColors.red, size: 36),
                    ),
                  ),
                  step(1, 'Download Pokepedia'),
                  step(2, 'Daftar, isi kode $code'),
                  step(3, 'Kupon aktif, langsung belanja'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  '$referralImageDir/badge-app-store.webp',
                  width: 96,
                ),
                const SizedBox(width: 8),
                Image.asset(
                  '$referralImageDir/badge-google-play.webp',
                  width: 100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 1080×1080 square image (02 §4), laid out at 360×360.
class ReferralSquareImage extends StatelessWidget {
  const ReferralSquareImage({
    super.key,
    required this.dashboard,
    required this.username,
  });

  final ReferralDashboard dashboard;
  final String username;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _creamBg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/images/horizontal-logo-light.webp',
                  height: 22,
                ),
                const Spacer(),
                if (username.isNotEmpty) _invitePill('dari @$username'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gratis ongkir buat kartu pertamamu!',
              textAlign: TextAlign.center,
              style: handStyle(ReferralColors.ink, size: 30),
            ),
            Expanded(
              child: Transform.rotate(
                angle: -0.05,
                child: Image.asset('$referralImageDir/kupon-coretan.webp'),
              ),
            ),
            _hardShadowCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daftar pakai kode',
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ReferralColors.muted,
                          ),
                        ),
                        Text(
                          'pokepedia.id',
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            color: ReferralColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    dashboard.code ?? '',
                    style: handStyle(ReferralColors.red, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
