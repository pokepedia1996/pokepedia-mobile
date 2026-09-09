import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/chat_repository.dart';
import '../repository/models/chat_models.dart';
import '../usecase/chat_notifier.dart';
import 'widgets/chat_party_colors.dart';
import 'widgets/chat_event_cards.dart';

/// Ports `components/chat/chat-room.tsx`, backed by `chat_messages` with a
/// realtime subscription for the other side's replies.
///
/// Opens in one of two states: an existing room (by [slug]), or a
/// conversation with a [target] that has no room yet — rooms are created
/// lazily by `ensure_direct_room` on the first message.
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({super.key, this.slug, this.target, this.titleHint});

  final String? slug;
  final ChatTarget? target;

  /// The name the caller already knows, shown until the room resolves.
  final String? titleHint;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Picked but not yet sent — web's `pendingImage`, shown above the composer
  /// so it can be swapped or dropped before it goes.
  File? _pendingImage;

  late final ChatThreadArg _arg = (
    slug: widget.slug,
    otherUserId: widget.target?.otherUserId,
    listingId: widget.target?.listingId,
    title: widget.target?.title ?? widget.titleHint ?? 'Percakapan',
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The list is reversed, so its far end is the top of the conversation —
  /// reaching it asks for the page above.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 300) return;
    ref.read(chatThreadProvider(_arg).notifier).loadOlder();
  }

  Future<void> _send() async {
    final text = _controller.text;
    final image = _pendingImage;
    if (text.trim().isEmpty && image == null) return;

    _controller.clear();
    setState(() => _pendingImage = null);
    await _guard(
      () =>
          ref.read(chatThreadProvider(_arg).notifier).send(text, image: image),
    );
  }

  /// Picks a photo to go with the next message. Only staged here — nothing is
  /// uploaded until send, since the upload needs a room to file it under.
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image, size: 20),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera, size: 20),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      // Enough of a cap to keep a 48MP original off the heap on the way to
      // the compressor, which does the real resizing.
      maxWidth: 3000,
    );
    if (picked == null || !mounted) return;
    setState(() => _pendingImage = File(picked.path));
  }

  Future<void> _retry(ChatMessage message) {
    return _guard(
      () => ref.read(chatThreadProvider(_arg).notifier).retry(message),
    );
  }

  /// Runs a send and turns whatever it throws into a snackbar — the same
  /// handling whether the message is new or a second attempt.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ChatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Pesan gagal dikirim')));
    }
  }

  /// Offers the two ways out of a message that wouldn't send.
  Future<void> _failedActions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.rotateCw, size: 20),
              title: const Text('Kirim ulang'),
              onTap: () => Navigator.of(sheetContext).pop('retry'),
            ),
            ListTile(
              leading: Icon(
                LucideIcons.trash2,
                size: 20,
                color: sheetContext.appColors.error,
              ),
              title: const Text('Hapus pesan'),
              onTap: () => Navigator.of(sheetContext).pop('discard'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'retry') await _retry(message);
    if (action == 'discard') {
      ref.read(chatThreadProvider(_arg).notifier).discard(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chatThreadProvider(_arg));
    final state = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _ThreadTitle(
          name: state?.title ?? _arg.title,
          username: state?.room?.otherUsername,
          avatarUrl: state?.room?.otherAvatarUrl,
          userId: state?.room?.otherUserId,
        ),
      ),
      body: async.when(
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat percakapan',
        ),
        data: (state) {
          if (state.missing || (widget.slug == null && widget.target == null)) {
            return const EmptyState(
              icon: LucideIcons.messageCircle,
              title: 'Percakapan tidak ditemukan',
              description: 'Percakapan ini mungkin sudah dihapus.',
            );
          }

          final rows = _threadRows(state.messages);
          final viewerId = ref.watch(authProvider).valueOrNull?.id;
          // Only the newest card for each offer carries buttons, so an older
          // counter in the scrollback reads as history rather than a live
          // choice — `latestMsgIdBySlug` on the web.
          final latestOfferMessageId = _latestOfferMessageIds(state.messages);
          return Column(
            children: [
              Expanded(
                child: state.messages.isEmpty
                    ? EmptyState(
                        icon: LucideIcons.messageCircle,
                        title: 'Mulai percakapan',
                        description: 'Kirim pesan pertamamu ke ${state.title}.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        // Newest at the bottom, and the list sits there on
                        // open without a scroll jump.
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        // One past the rows for the spinner that sits above
                        // the oldest message while a page is in flight.
                        itemCount: rows.length + (state.loadingMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= rows.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final row = rows[rows.length - 1 - i];
                          return switch (row) {
                            _DayRow(:final day) => _DaySeparator(day: day),
                            _MessageRow(:final message, :final startsRun) =>
                              _Bubble(
                                viewerId: viewerId,
                                room: state.room,
                                startsRun: startsRun,
                                readByOthers: state.isReadByOthers(message.id),
                                isLatestOffer:
                                    message.offerEvent != null &&
                                    latestOfferMessageId[message
                                            .offerEvent!
                                            .offerSlug] ==
                                        message.id,
                                message: message,
                                onFailedTap: message.failed
                                    ? () => _failedActions(message)
                                    : null,
                              ),
                          };
                        },
                      ),
              ),
              _Composer(
                controller: _controller,
                sending: state.sending,
                pendingImage: _pendingImage,
                onSend: _send,
                onAttach: _pickImage,
                onDropImage: () => setState(() => _pendingImage = null),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The thread as it is drawn: the messages with a day separator wherever the
/// date turns over, oldest first.
List<_ThreadRow> _threadRows(List<ChatMessage> messages) {
  final rows = <_ThreadRow>[];
  DateTime? lastDay;
  String? lastIdentitySender;

  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final day = DateUtils.dateOnly(message.createdAt);
    if (lastDay == null || day != lastDay) {
      rows.add(_DayRow(day));
      lastDay = day;
      // A new day restarts the run, so the first message under a separator
      // always introduces its sender.
      lastIdentitySender = null;
    }

    // Web's `showName`: the first message after the speaker changes is the
    // one that carries the avatar, the name and the bubble's tail. A card
    // (`listing_context`, an order or offer event) breaks the run, since it
    // isn't anybody speaking.
    final startsRun =
        !message.isEvent &&
        (lastIdentitySender == null || lastIdentitySender != message.senderId);
    lastIdentitySender = message.isEvent ? null : message.senderId;

    rows.add(_MessageRow(message: message, startsRun: startsRun));
  }
  return rows;
}

/// The newest `offer_event` message id per offer slug.
Map<String, int> _latestOfferMessageIds(List<ChatMessage> messages) {
  final latest = <String, int>{};
  for (final message in messages) {
    final slug = message.offerEvent?.offerSlug;
    if (slug == null) continue;
    if (message.id > (latest[slug] ?? 0)) latest[slug] = message.id;
  }
  return latest;
}

sealed class _ThreadRow {
  const _ThreadRow();
}

class _DayRow extends _ThreadRow {
  const _DayRow(this.day);
  final DateTime day;
}

class _MessageRow extends _ThreadRow {
  const _MessageRow({required this.message, required this.startsRun});

  final ChatMessage message;

  /// First of a run from the same sender — the one that carries the avatar,
  /// the sender's name and the bubble's tail.
  final bool startsRun;
}

/// Who you're talking to, beside their picture.
/// Ports the web room's header: the other party's picture, their name, and
/// their handle after it in small muted type.
class _ThreadTitle extends StatelessWidget {
  const _ThreadTitle({
    required this.name,
    this.username,
    this.avatarUrl,
    this.userId,
  });

  final String name;
  final String? username;
  final String? avatarUrl;

  /// Colours the fallback initials, so the header and this person's bubbles
  /// agree.
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        _PartyAvatar(name: name, userId: userId, imageUrl: avatarUrl, size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
        ),
        if (username != null && username!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            '@$username',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.badge(
              context.mutedForeground,
            ).copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ],
    );
  }
}

/// The circle a party is drawn as: their picture, or their initials on the
/// colour their id hashes to — the same one web puts behind them.
class _PartyAvatar extends StatelessWidget {
  const _PartyAvatar({
    required this.name,
    required this.size,
    this.userId,
    this.imageUrl,
  });

  final String name;
  final double size;
  final String? userId;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return UserAvatar(username: name, imageUrl: url, size: size);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chatPartyColor(userId ?? name).avatar,
        shape: BoxShape.circle,
      ),
      child: Text(chatInitials(name), style: AppTypography.badge(Colors.white)),
    );
  }
}

/// "Hari ini" / "Kemarin" / the date, between two days of conversation.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final daysApart = today.difference(day).inDays;
    final label = switch (daysApart) {
      <= 0 => 'Hari ini',
      1 => 'Kemarin',
      _ => formatShortDateId(day),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.appColors.secondary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: AppTypography.caption(context.mutedForeground),
          ),
        ),
      ),
    );
  }
}

/// One message, laid out the way the web room lays it out: the speaker's
/// picture beside the first bubble of their run, their name inside it in
/// their own colour, and the clock — with read ticks on your own — tucked
/// against the text's last line.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.startsRun,
    this.room,
    this.viewerId,
    this.readByOthers = false,
    this.isLatestOffer = false,
    this.onFailedTap,
  });

  final ChatMessage message;

  /// First of a run: draws the avatar, the name and the tail.
  final bool startsRun;

  /// Where the other party's name and picture come from. A direct room has
  /// exactly one of them, which is who any message not from you is by.
  final ChatRoom? room;

  final String? viewerId;

  /// Everyone else in the room has read this one — the green ticks.
  final bool readByOthers;

  final bool isLatestOffer;

  /// Opens the retry/discard sheet. Null unless the send was rejected.
  final VoidCallback? onFailedTap;

  static const _avatarSize = 28.0;
  static const _gutter = 8.0;

  @override
  Widget build(BuildContext context) {
    // Room events (`listing_context`, `order_event`, `offer_event`) are notes
    // about the conversation, not speech in it — each gets the card web draws
    // for it.
    if (message.isEvent) {
      return ChatEventCard(
        message: message,
        viewerId: viewerId,
        isLatestOffer: isLatestOffer,
      );
    }

    final mine = message.fromMe;
    final senderName = room?.title ?? 'Pengguna';
    final senderId = message.senderId.isEmpty
        ? (room?.otherUserId ?? senderName)
        : message.senderId;

    return Padding(
      // Web opens a run with `mt-3` and keeps the rest of it tight.
      padding: EdgeInsets.only(top: startsRun ? 10 : 2, bottom: 0),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The other side's picture, once per run — and a gap the width of
          // it under the rest, so a run stays in one column.
          if (!mine) ...[
            if (startsRun)
              _PartyAvatar(
                name: senderName,
                userId: senderId,
                imageUrl: room?.otherAvatarUrl,
                size: _avatarSize,
              )
            else
              const SizedBox(width: _avatarSize),
            const SizedBox(width: _gutter),
          ],
          Flexible(
            child: ConstrainedBox(
              // `max-w-[85%]`, measured against the row rather than the
              // screen so the avatar column doesn't push a bubble off it.
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.85,
              ),
              child: _BubbleBody(
                message: message,
                mine: mine,
                startsRun: startsRun,
                readByOthers: readByOthers,
                senderName: senderName,
                senderId: senderId,
                onFailedTap: onFailedTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bubble itself, without the avatar column.
class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.mine,
    required this.startsRun,
    required this.readByOthers,
    required this.senderName,
    required this.senderId,
    this.onFailedTap,
  });

  final ChatMessage message;
  final bool mine;
  final bool startsRun;
  final bool readByOthers;
  final String senderName;
  final String senderId;
  final VoidCallback? onFailedTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final background = mine ? semantic.chatMine : semantic.chatTheirs;
    // Dark text on both bubbles, as web has: they are tints, not fills.
    final foreground = colors.onSurface;
    final showName = startsRun && !mine;

    const corner = Radius.circular(AppRadius.md);

    return GestureDetector(
      onTap: onFailedTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: message.isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                // The corner the tail joins is squared off, like web's
                // `rounded-tl-none`.
                topLeft: showName ? Radius.zero : corner,
                topRight: corner,
                bottomLeft: corner,
                bottomRight: corner,
              ),
              border: message.failed
                  ? Border.all(color: colors.error, width: 1)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionSemibold(
                        chatPartyColor(senderId).text,
                      ).copyWith(fontSize: 13),
                    ),
                  ),
                if (message.isImage)
                  _ImageAttachment(message: message, foreground: foreground),
                // Text and stamp on one line, the stamp bottom-aligned
                // against it — web's `flex items-end gap-1.5`.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.text.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            message.text,
                            style: AppTypography.bodySm(foreground),
                          ),
                        ),
                      ),
                    _Stamp(
                      message: message,
                      mine: mine,
                      readByOthers: readByOthers,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // The little wedge that points at the speaker, drawn outside the
          // bubble's own box like web's absolutely-positioned SVG.
          if (showName)
            Positioned(
              left: -7,
              top: 0,
              child: CustomPaint(
                size: const Size(7, 11),
                painter: _TailPainter(color: background),
              ),
            ),
        ],
      ),
    );
  }
}

/// "15.43" and, on your own messages, whether they have been read.
class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.message,
    required this.mine,
    required this.readByOthers,
  });

  final ChatMessage message;
  final bool mine;
  final bool readByOthers;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = context.mutedForeground.withValues(alpha: 0.7);

    // A pending bubble has no server timestamp worth showing, and a failed
    // one needs saying plainly rather than in ticks.
    if (message.failed) {
      return Text(
        'Gagal terkirim · ketuk untuk kirim ulang',
        style: AppTypography.badge(colors.error),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.pending ? 'Mengirim...' : message.sentAt,
            style: AppTypography.badge(
              muted,
            ).copyWith(fontSize: 10, fontWeight: FontWeight.w400),
          ),
          if (mine && !message.pending && message.id > 0) ...[
            const SizedBox(width: 2),
            Icon(
              LucideIcons.checkCheck,
              size: 13,
              color: readByOthers ? context.appSemantic.success : muted,
            ),
          ],
        ],
      ),
    );
  }
}

/// The bubble's tail: a wedge filled with the bubble's own colour, matching
/// the `M11 0 H0 C4 0 11 7 11 11 Z` path web draws.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, 0)
      ..cubicTo(
        size.width * 0.36,
        0,
        size.width,
        size.height * 0.64,
        size.width,
        size.height,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.color != color;
}

/// A photo someone sent. Web sizes these `max-h-[300px] max-w-[250px]` and
/// opens them in a lightbox on tap.
///
/// A message still on its way up draws the picked file straight off disk, so
/// the photo is on screen before the upload finishes.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.message, required this.foreground});

  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final local = message.localImagePath;
    final url = message.mediaUrl;

    final Widget picture;
    if (local != null) {
      picture = Image.file(
        File(local),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _unavailable(context),
      );
    } else if (url != null && url.isNotEmpty) {
      picture = Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _unavailable(context),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 140,
                width: 140,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      );
    } else {
      // The object is gone from the bucket, or couldn't be signed.
      picture = _unavailable(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 250),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: GestureDetector(
              // Only a photo that has somewhere to open is tappable.
              onTap: url == null || url.isEmpty
                  ? null
                  : () => showImageLightbox(context, imageUrl: url),
              child: picture,
            ),
          ),
        ),
        // An image row can still carry a caption in `content`.
        if (message.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(message.text, style: AppTypography.bodySm(foreground)),
          ),
        ],
      ],
    );
  }

  /// Web's "Gambar tidak tersedia lagi" strip.
  Widget _unavailable(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: context.appColors.secondary,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 16, color: context.mutedForeground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Gambar tidak tersedia lagi',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.pendingImage,
    required this.onSend,
    required this.onAttach,
    required this.onDropImage,
  });

  final TextEditingController controller;
  final bool sending;
  final File? pendingImage;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onDropImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final staged = pendingImage;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (staged != null)
              _PendingImage(file: staged, onRemove: onDropImage),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.imagePlus, size: 22),
                  color: context.mutedForeground,
                  tooltip: 'Kirim foto',
                  onPressed: sending ? null : onAttach,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: ChatRepository.maxMessageLength,
                    decoration: const InputDecoration(
                      hintText: 'Tulis pesan...',
                      // The counter only earns its space near the ceiling.
                      counterText: '',
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                // Rebuilt on every keystroke so the button can go dead on an
                // empty field — tapping send with nothing typed did nothing,
                // with no way to tell that from a silent failure. A staged
                // photo is a message on its own, caption or not.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final canSend =
                        !sending &&
                        (value.text.trim().isNotEmpty || staged != null);
                    return IconButton(
                      icon: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              LucideIcons.send,
                              color: canSend
                                  ? colors.primary
                                  : context.mutedForeground,
                            ),
                      onPressed: canSend ? onSend : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The staged photo above the composer, with the way to drop it again.
class _PendingImage extends StatelessWidget {
  const _PendingImage({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.file(
              file,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: context.appColors.secondary,
                child: Icon(
                  LucideIcons.imageOff,
                  size: 18,
                  color: context.mutedForeground,
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.appColors.onSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.x,
                  size: 12,
                  color: Theme.of(context).cardColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
