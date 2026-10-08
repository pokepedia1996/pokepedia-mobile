import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/open_dispute.dart';
import '../repository/models/order_model.dart';
import '../usecase/orders_notifier.dart';
import '../utils/dispute_reasons.dart';
import 'widgets/order_thumbnail.dart';

/// Ports `app/orders/[slug]/dispute/open` and its `[reason]` step: pick what
/// went wrong, then either report the parcel lost or build web's basket of
/// damaged / not-as-described / short complaints and submit it in one batch.
class OrderDisputePage extends ConsumerStatefulWidget {
  const OrderDisputePage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<OrderDisputePage> createState() => _OrderDisputePageState();
}

/// A complaint committed to the basket — web's `BasketEntry`.
class _Entry {
  const _Entry({
    required this.reason,
    required this.itemSlugs,
    required this.detail,
    required this.photos,
    required this.videoUrl,
    required this.shortQty,
    required this.resolution,
  });

  final DisputeReason reason;
  final List<String> itemSlugs;
  final String detail;
  final List<DisputeEvidencePhoto> photos;
  final String videoUrl;
  final Map<String, int> shortQty;
  final DisputeResolution? resolution;
}

/// The complaint being written — web's `DraftState`.
class _Draft {
  _Draft({
    required this.reason,
    required this.selected,
    required this.shortQty,
    this.editingIndex,
    String detail = '',
    String videoUrl = '',
    List<DisputeEvidencePhoto>? photos,
    this.resolution,
  }) : detail = TextEditingController(text: detail),
       videoUrl = TextEditingController(text: videoUrl),
       photos = photos ?? [];

  DisputeReason reason;
  final Set<String> selected;
  final Map<String, int> shortQty;
  final int? editingIndex;
  final TextEditingController detail;
  final TextEditingController videoUrl;
  final List<DisputeEvidencePhoto> photos;
  DisputeResolution? resolution;

  void dispose() {
    detail.dispose();
    videoUrl.dispose();
  }
}

const _snadReasons = [
  DisputeReason.damaged,
  DisputeReason.notAsDescribed,
  DisputeReason.short,
];

class _OrderDisputePageState extends ConsumerState<OrderDisputePage> {
  DisputeReason? _picked;
  final _entries = <_Entry>[];
  _Draft? _draft;
  bool _submitting = false;

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Set<String> _basketedSlugs({int? exceptIndex}) => {
    for (var i = 0; i < _entries.length; i++)
      if (i != exceptIndex) ..._entries[i].itemSlugs,
  };

  void _pickReason(DisputeReason reason, OpenDisputeEligibility eligibility) {
    setState(() {
      _picked = reason;
      if (reason.needsEvidence) _openDraft(eligibility, reason);
    });
  }

  void _openDraft(OpenDisputeEligibility eligibility, DisputeReason reason) {
    final taken = _basketedSlugs();
    final available = [
      for (final item in eligibility.snadItems)
        if (!taken.contains(item.slug)) item,
    ];
    _draft?.dispose();
    _draft = _Draft(
      reason: reason,
      selected: {for (final item in available) item.slug},
      shortQty: {for (final item in available) item.slug: 1},
      resolution: reason == DisputeReason.short
          ? DisputeResolution.refundOnly
          : null,
    );
  }

  void _cancelDraft() {
    setState(() {
      _draft?.dispose();
      _draft = null;
      if (_entries.isEmpty) _picked = null;
    });
  }

  void _editEntry(int index) {
    final entry = _entries[index];
    setState(() {
      _draft?.dispose();
      _draft = _Draft(
        reason: entry.reason,
        selected: {...entry.itemSlugs},
        shortQty: {...entry.shortQty},
        editingIndex: index,
        detail: entry.detail,
        videoUrl: entry.videoUrl,
        photos: [...entry.photos],
        resolution: entry.resolution,
      );
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _entries.removeAt(index);
      if (_entries.isEmpty && _draft == null) _picked = null;
    });
  }

  /// Ports `commitDraft`'s checks, in its order and with its messages.
  void _commitDraft() {
    final draft = _draft;
    if (draft == null) return;
    final detail = draft.detail.text.trim();
    final video = draft.videoUrl.text.trim();

    final problem = switch (draft) {
      _ when draft.selected.isEmpty => 'Pilih minimal satu barang',
      _ when detail.isEmpty => 'Alasan wajib diisi',
      _ when draft.reason != DisputeReason.short && draft.resolution == null =>
        'Pilih penyelesaian yang diinginkan',
      _ when draft.photos.isEmpty => 'Lampirkan minimal 1 foto bukti',
      _ when video.isNotEmpty && !isHttpsUrl(video) =>
        'Link video harus https://',
      _ when video.length > disputeMaxVideoUrl => 'Link video terlalu panjang',
      _ => null,
    };
    if (problem != null) {
      _toast(problem);
      return;
    }

    final entry = _Entry(
      reason: draft.reason,
      itemSlugs: draft.selected.toList(),
      detail: detail,
      photos: [...draft.photos],
      videoUrl: video,
      shortQty: {
        for (final slug in draft.selected) slug: draft.shortQty[slug] ?? 1,
      },
      resolution: draft.reason == DisputeReason.short
          ? DisputeResolution.refundOnly
          : draft.resolution,
    );
    setState(() {
      final index = draft.editingIndex;
      if (index != null) {
        _entries[index] = entry;
      } else {
        _entries.add(entry);
      }
      draft.dispose();
      _draft = null;
    });
  }

  Future<void> _addPhoto() async {
    final draft = _draft;
    if (draft == null || draft.photos.length >= disputeMaxPhotos) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final extension = picked.name.split('.').last.toLowerCase();
    final contentType = disputePhotoMimeByExtension[extension];
    if (contentType == null) {
      _toast('Format harus JPG, PNG, atau WebP');
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > disputeMaxPhotoBytes) {
      _toast('Ukuran foto maksimal 5MB');
      return;
    }
    setState(
      () => draft.photos.add(
        DisputeEvidencePhoto(
          bytes: bytes,
          contentType: contentType,
          extension: extension == 'jpeg' ? 'jpg' : extension,
        ),
      ),
    );
  }

  /// Ports `handleFinalSubmit`: lines left out of every complaint are paid
  /// out to the seller, so the buyer is told which and how much first.
  Future<void> _confirmSubmit(
    OrderModel order,
    OpenDisputeEligibility eligibility,
  ) async {
    final basketed = _basketedSlugs();
    final leftover = [
      for (final item in eligibility.snadItems)
        if (!basketed.contains(item.slug)) item,
    ];
    if (leftover.isEmpty) return _submit(order, releaseLeftover: false);

    final total = leftover.fold(0, (sum, item) => sum + item.subtotal);
    final names = leftover
        .map(
          (item) => item.matchedQuantity > 1
              ? '${item.card.name} ×${item.matchedQuantity}'
              : item.card.name,
        )
        .join(', ');
    var confirmed = false;
    await showConfirmDialog(
      context,
      title: 'Barang yang tidak dikomplain akan diserahkan ke penjual',
      description:
          'Dana untuk barang berikut langsung dicairkan ke penjual dan tidak '
          'bisa dikomplain lagi: $names. Total dicairkan '
          '${formatRupiah(total)}.',
      confirmLabel: 'Lanjutkan',
      loadingLabel: 'Memproses...',
      cancelLabel: 'Kembali',
      onConfirm: () async => confirmed = true,
    );
    // Submitted after the dialog has closed: a submit that navigates away
    // while the dialog is still up would have the dialog pop the new route.
    if (confirmed && mounted) await _submit(order, releaseLeftover: true);
  }

  /// Ports `submitBasket`. One order means one settlement folder, so each
  /// entry's photos upload once under the first chosen line's settlement.
  Future<void> _submit(
    OrderModel order, {
    required bool releaseLeftover,
  }) async {
    if (_entries.isEmpty || _submitting) return;
    final repository = ref.read(ordersRepositoryProvider);
    final itemsBySlug = {for (final item in order.items) item.slug: item};

    setState(() => _submitting = true);
    try {
      final payload = <OpenDisputeEntry>[];
      for (final entry in _entries) {
        final settlementSlug =
            itemsBySlug[entry.itemSlugs.first]?.settlementSlug;
        if (settlementSlug == null) {
          _toast('Gagal mengirim komplain. Coba lagi.');
          return;
        }
        final photoUrls = await repository.uploadDisputeEvidence(
          settlementSlug,
          entry.photos,
        );
        payload.add(
          OpenDisputeEntry(
            reason: entry.reason,
            itemSlugs: entry.itemSlugs,
            detail: entry.detail,
            photoUrls: photoUrls,
            videoUrl: entry.videoUrl,
            shortQuantity: entry.shortQty,
            requestedResolution: entry.resolution,
          ),
        );
      }

      final anchorSlug = _entries.first.itemSlugs.first;
      final result = await repository.openDisputes(anchorSlug, payload);
      if (result.error != null) {
        _toast(result.error!);
        return;
      }
      if (releaseLeftover) {
        await repository.releaseNonDisputedSiblings(anchorSlug);
      }
      _onFiled('Komplain terkirim', openDispute: result.disputesOpened == 1);
    } catch (_) {
      _toast('Gagal mengunggah bukti foto. Coba lagi.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reportNotReceived(OrderModel order) async {
    final delivered = order.shipmentStatus == 'received';
    var confirmed = false;
    await showConfirmDialog(
      context,
      title: delivered
          ? 'Laporkan barang tidak diterima?'
          : 'Laporkan paket tidak sampai?',
      description: delivered
          ? 'Laporan diteruskan ke penjual untuk ditanggapi. Penjual punya '
                'waktu 2 hari untuk merespons.'
          : 'Laporan ini akan diteruskan ke tim kami untuk ditinjau. Seluruh '
                'tenggat waktu otomatis pada pesanan ini akan dijeda hingga '
                'tim kami menyelesaikan laporan.',
      confirmLabel: 'Lanjutkan',
      loadingLabel: 'Mengajukan...',
      destructive: false,
      onConfirm: () async => confirmed = true,
    );
    if (!confirmed || !mounted) return;

    final shipmentSlug = order.shipmentSlug;
    if (shipmentSlug == null) {
      _toast('Data pengiriman tidak tersedia');
      return;
    }
    setState(() => _submitting = true);
    final error = await ref
        .read(ordersRepositoryProvider)
        .reportNotReceived(shipmentSlug);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      _toast(error);
      return;
    }
    _onFiled(
      'Laporan terkirim. Tim kami akan segera menindaklanjuti.',
      openDispute: true,
    );
  }

  void _onFiled(String message, {required bool openDispute}) {
    ref.invalidate(orderDetailProvider(widget.slug));
    ref.invalidate(orderDisputeProvider(widget.slug));
    ref.invalidate(ordersProvider);
    if (!mounted) return;
    _toast(message);
    if (openDispute) {
      context.pushReplacement(Routes.orderDispute(widget.slug));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderDetailProvider(widget.slug));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat pesanan')),
          data: (order) {
            if (order == null) {
              return const EmptyState(
                icon: LucideIcons.receipt,
                title: 'Pesanan tidak ditemukan',
              );
            }
            final eligibility = openDisputeEligibility(order);
            if (!eligibility.canOpenAny && _entries.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.shieldAlert,
                title: 'Komplain belum bisa diajukan',
                description:
                    'Komplain bisa diajukan setelah paket tiba atau melewati '
                    'estimasi waktu tiba.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: switch (_picked) {
                null => [
                  _ReasonList(
                    eligibility: eligibility,
                    onPick: (reason) => _pickReason(reason, eligibility),
                  ),
                ],
                DisputeReason.notReceived => [
                  _NotReceivedView(
                    order: order,
                    busy: _submitting,
                    onBack: () => setState(() => _picked = null),
                    onSubmit: () => _reportNotReceived(order),
                  ),
                ],
                _ => _basketChildren(order, eligibility),
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _basketChildren(
    OrderModel order,
    OpenDisputeEligibility eligibility,
  ) {
    final colors = context.appColors;
    final draft = _draft;
    final itemsBySlug = {for (final item in order.items) item.slug: item};
    final taken = _basketedSlugs(exceptIndex: draft?.editingIndex);
    final remaining = [
      for (final item in eligibility.snadItems)
        if (!taken.contains(item.slug)) item,
    ];
    final canAddMore = draft == null && remaining.isNotEmpty;

    return [
      if (_entries.isNotEmpty) ...[
        _InfoNote(
          text:
              'Ada lebih dari 1 masalah? Kamu bisa tambah komplain untuk '
              'masalah lainnya sebelum klik "Ajukan Komplain".',
        ),
        const SizedBox(height: 12),
      ],
      for (var i = 0; i < _entries.length; i++) ...[
        _EntryCard(
          entry: _entries[i],
          itemsBySlug: itemsBySlug,
          disabled: _submitting || draft != null,
          onEdit: () => _editEntry(i),
          onRemove: () => _removeEntry(i),
        ),
        const SizedBox(height: 12),
      ],
      if (draft != null) ...[
        _DraftEditor(
          draft: draft,
          items: remaining,
          disabled: _submitting,
          onChanged: () => setState(() {}),
          onAddPhoto: _addPhoto,
          onCancel: _cancelDraft,
          onCommit: _commitDraft,
        ),
        const SizedBox(height: 12),
      ],
      if (canAddMore) ...[
        OutlinedButton.icon(
          onPressed: _submitting
              ? null
              : () => setState(
                  () => _openDraft(eligibility, DisputeReason.damaged),
                ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Tambah komplain lain'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_entries.isNotEmpty && draft == null)
        ElevatedButton(
          onPressed: _submitting
              ? null
              : () => _confirmSubmit(order, eligibility),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: colors.error,
          ),
          child: Text(_submitting ? 'Mengirim...' : 'Ajukan Komplain'),
        ),
    ];
  }
}

/// Ports `reason-list.tsx` — every reason is listed, the ones this order
/// can't use yet greyed out rather than hidden.
class _ReasonList extends StatelessWidget {
  const _ReasonList({required this.eligibility, required this.onPick});

  final OpenDisputeEligibility eligibility;
  final ValueChanged<DisputeReason> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _Card(
      children: [
        Text('Ajukan Komplain', style: AppTypography.h2(colors.onSurface)),
        const SizedBox(height: 4),
        Text(
          'Ada masalah apa di pesananmu?',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        const SizedBox(height: 16),
        for (final reason in DisputeReason.values) ...[
          Opacity(
            opacity: eligibility.isEnabled(reason) ? 1 : 0.5,
            child: InkWell(
              onTap: eligibility.isEnabled(reason)
                  ? () => onPick(reason)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reason.optionLabel,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: context.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Ports `not-received-form.tsx`.
class _NotReceivedView extends StatelessWidget {
  const _NotReceivedView({
    required this.order,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
  });

  final OrderModel order;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final info = order.shipmentStatus == 'received'
        ? notReceivedDeliveredInfo
        : DisputeReason.notReceived.resolutionInfo;

    return _Card(
      children: [
        _SelectedReason(
          reason: DisputeReason.notReceived,
          onChange: busy ? null : onBack,
        ),
        const SizedBox(height: 16),
        Text(
          DisputeReason.notReceived.itemsHeading,
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 8),
        for (final item in order.items) _ItemRow(item: item),
        const SizedBox(height: 12),
        _InfoNote(title: info.title, text: info.body),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: busy ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Ajukan Komplain'),
        ),
      ],
    );
  }
}

/// Ports `committed-entry-card.tsx`.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.itemsBySlug,
    required this.disabled,
    required this.onEdit,
    required this.onRemove,
  });

  final _Entry entry;
  final Map<String, OrderItemModel> itemsBySlug;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _Card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.reason.label,
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ),
            IconButton(
              tooltip: 'Ubah komplain',
              onPressed: disabled ? null : onEdit,
              icon: const Icon(LucideIcons.pencil, size: 16),
            ),
            IconButton(
              tooltip: 'Hapus komplain',
              onPressed: disabled ? null : onRemove,
              icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
            ),
          ],
        ),
        for (final slug in entry.itemSlugs)
          if (itemsBySlug[slug] case final item?)
            _ItemRow(
              item: item,
              trailing: entry.reason == DisputeReason.short
                  ? 'Kurang ${entry.shortQty[slug] ?? 1}'
                  : null,
            ),
        const SizedBox(height: 4),
        Text(
          entry.detail,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        const SizedBox(height: 4),
        Text(
          '${entry.photos.length} foto bukti'
          '${entry.resolution != null ? ' · ${entry.resolution!.label}' : ''}',
          style: AppTypography.caption(context.mutedForeground),
        ),
      ],
    );
  }
}

/// Ports `draft-editor.tsx` + `evidence-fields.tsx` + `resolution-picker.tsx`.
class _DraftEditor extends StatelessWidget {
  const _DraftEditor({
    required this.draft,
    required this.items,
    required this.disabled,
    required this.onChanged,
    required this.onAddPhoto,
    required this.onCancel,
    required this.onCommit,
  });

  final _Draft draft;
  final List<OrderItemModel> items;
  final bool disabled;
  final VoidCallback onChanged;
  final VoidCallback onAddPhoto;
  final VoidCallback onCancel;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isShort = draft.reason == DisputeReason.short;

    return _Card(
      children: [
        Text(
          'Masalah dipilih',
          style: AppTypography.overline(context.mutedForeground),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in _snadReasons)
              ChoiceChip(
                label: Text(reason.optionLabel),
                selected: draft.reason == reason,
                onSelected: disabled
                    ? null
                    : (_) {
                        draft.reason = reason;
                        if (reason == DisputeReason.short) {
                          draft.resolution = DisputeResolution.refundOnly;
                        }
                        onChanged();
                      },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          draft.reason.itemsHeading,
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          InkWell(
            onTap: disabled
                ? null
                : () {
                    if (!draft.selected.remove(item.slug)) {
                      draft.selected.add(item.slug);
                    }
                    onChanged();
                  },
            child: Row(
              children: [
                Icon(
                  draft.selected.contains(item.slug)
                      ? LucideIcons.squareCheck
                      : LucideIcons.square,
                  size: 18,
                  color: draft.selected.contains(item.slug)
                      ? colors.primary
                      : context.mutedForeground,
                ),
                const SizedBox(width: 10),
                Expanded(child: _ItemRow(item: item)),
                if (isShort && draft.selected.contains(item.slug))
                  _QtyStepper(
                    value: draft.shortQty[item.slug] ?? 1,
                    max: item.matchedQuantity,
                    onChanged: disabled
                        ? null
                        : (value) {
                            draft.shortQty[item.slug] = value;
                            onChanged();
                          },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          '${draft.reason.detailLabel} *',
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: draft.detail,
          enabled: !disabled,
          maxLines: 3,
          maxLength: disputeMaxDetail,
          decoration: const InputDecoration(
            hintText: 'Jelaskan apa yang terjadi...',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Foto bukti *',
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          '${draft.photos.length}/$disputeMaxPhotos foto '
          '(JPG/PNG/WebP, max 5MB)',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < draft.photos.length; i++)
              _PhotoTile(
                photo: draft.photos[i],
                onRemove: disabled
                    ? null
                    : () {
                        draft.photos.removeAt(i);
                        onChanged();
                      },
              ),
            if (draft.photos.length < disputeMaxPhotos)
              InkWell(
                onTap: disabled ? null : onAddPhoto,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.borderColor, width: 2),
                  ),
                  child: Icon(
                    LucideIcons.camera,
                    size: 20,
                    color: context.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Link video bukti',
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: draft.videoUrl,
          enabled: !disabled,
          keyboardType: TextInputType.url,
          maxLength: disputeMaxVideoUrl,
          decoration: const InputDecoration(
            hintText: 'https://drive.google.com/...',
            helperText: 'Opsional. Tempel link YouTube / Google Drive',
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        if (isShort)
          _InfoNote(
            title: DisputeReason.short.resolutionInfo.title,
            text: DisputeReason.short.resolutionInfo.body,
          )
        else ...[
          Text(
            'Penyelesaian yang diminta *',
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          for (final resolution in DisputeResolution.values)
            InkWell(
              onTap: disabled
                  ? null
                  : () {
                      draft.resolution = resolution;
                      onChanged();
                    },
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      draft.resolution == resolution
                          ? LucideIcons.circleDot
                          : LucideIcons.circle,
                      size: 18,
                      color: draft.resolution == resolution
                          ? colors.primary
                          : context.mutedForeground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resolution.label,
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                          Text(
                            resolution.body,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: disabled ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Batal'),
              ),
            ),
            Expanded(
              child: ElevatedButton(
                onPressed: disabled || draft.selected.isEmpty ? null : onCommit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text(
                  'Simpan komplain ini',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectedReason extends StatelessWidget {
  const _SelectedReason({required this.reason, required this.onChange});

  final DisputeReason reason;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Masalah dipilih',
                style: AppTypography.overline(context.mutedForeground),
              ),
              const SizedBox(height: 4),
              Text(
                reason.optionLabel,
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Ganti')),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.trailing});

  final OrderItemModel item;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          OrderThumbnail(
            imageUrl: item.card.imageUrl,
            size: 44,
            radius: AppRadius.sm,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '${item.matchedQuantity} × ${formatRupiah(item.matchPrice)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppTypography.captionSemibold(colors.onSurface),
            ),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Kurangi',
          visualDensity: VisualDensity.compact,
          onPressed: change == null || value <= 1
              ? null
              : () => change(value - 1),
          icon: const Icon(LucideIcons.minus, size: 14),
        ),
        Text(
          '$value',
          style: AppTypography.bodySmSemibold(context.appColors.onSurface),
        ),
        IconButton(
          tooltip: 'Tambah',
          visualDensity: VisualDensity.compact,
          onPressed: change == null || value >= max
              ? null
              : () => change(value + 1),
          icon: const Icon(LucideIcons.plus, size: 14),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onRemove});

  final DisputeEvidencePhoto photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Image.memory(photo.bytes, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text, this.title});

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: context.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                Text(
                  text,
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
