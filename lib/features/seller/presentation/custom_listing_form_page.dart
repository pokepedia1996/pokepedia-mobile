import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/errors/user_message.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_url.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/card_language_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/app_loader.dart';
import '../repository/custom_listings_repository.dart';
import '../repository/models/custom_listing_form.dart';
import '../repository/seller_listings_repository.dart';
import 'widgets/add_listing_sheet.dart';
import 'widgets/custom_photo_grid.dart';
import 'widgets/seller_switch.dart';

/// "Listing custom" — a seller's own title, photos, price and stock, with the
/// catalog cards inside it tagged. Web's `CustomListingForm`, for a new
/// listing ([slug] null) or one already saved.
///
/// A draft can be saved half-filled and picked up from the Draft tab. A
/// published listing has no draft to fall back to: its edits save straight
/// to the live listing.
///
/// Pops with true once a listing is published or updated, so Kelola Listing
/// can reload.
class CustomListingFormPage extends ConsumerStatefulWidget {
  const CustomListingFormPage({super.key, this.slug});

  final String? slug;

  @override
  ConsumerState<CustomListingFormPage> createState() =>
      _CustomListingFormPageState();
}

enum _Saving { draft, publish }

class _CustomListingFormPageState extends ConsumerState<CustomListingFormPage> {
  CustomListingFormValue? _value;

  /// What the page was opened on: whether it is a live listing being edited
  /// stays fixed, whatever is saved meanwhile.
  CustomListingFormValue? _initial;
  Object? _loadError;
  bool _notFound = false;

  _Saving? _saving;
  bool _uploading = false;

  /// Field errors stay quiet until a publish is tried.
  bool _showErrors = false;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();

  bool get _isLive => !(_initial?.isDraft ?? true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _notFound = false;
    });
    try {
      final slug = widget.slug;
      final CustomListingFormValue? value;
      if (slug == null) {
        // A new listing starts from the seller's Preferensi, as web's does.
        final defaults = await ref
            .read(sellerListingsRepositoryProvider)
            .fetchListingDefaults();
        value = CustomListingFormValue.blank(
          acceptsOffers: defaults.acceptsOffers,
          autoRelist: defaults.autoRelist,
        );
      } else {
        value = await ref
            .read(customListingsRepositoryProvider)
            .fetchForEdit(slug);
      }
      if (!mounted) return;
      if (value == null) {
        setState(() => _notFound = true);
        return;
      }
      _title.text = value.title;
      _description.text = value.description;
      _price.text = value.price == null ? '' : formatRupiah(value.price!);
      setState(() {
        _value = value;
        _initial = value;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _update(CustomListingFormValue Function(CustomListingFormValue) patch) {
    final value = _value;
    if (value == null) return;
    setState(() => _value = patch(value));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _save({required bool publish}) async {
    final value = _value;
    if (value == null || _saving != null || _uploading) return;
    FocusScope.of(context).unfocus();
    if (publish) {
      final blocker = value.publishBlocker;
      if (blocker != null) {
        setState(() => _showErrors = true);
        _toast(blocker);
        return;
      }
    }
    setState(() => _saving = publish ? _Saving.publish : _Saving.draft);
    final result = await ref
        .read(customListingsRepositoryProvider)
        .save(value, publish: publish);
    if (!mounted) return;
    setState(() => _saving = null);

    final slug = result.slug;
    if (slug == null) {
      _toast(result.error ?? 'Gagal menyimpan listing.');
      return;
    }
    if (result.published) {
      _toast(_isLive ? 'Listing diperbarui.' : 'Listing dipasang.');
      Navigator.of(context).pop(true);
      return;
    }
    // Saved as a draft: the next save updates this one instead of making
    // another.
    _update((v) => v.copyWith(slug: slug));
    _toast('Draft tersimpan');
  }

  Future<void> _tagCards() async {
    final picks = await showTagCardsSheet(context);
    if (picks == null || picks.isEmpty || !mounted) return;
    _update(
      (v) => v.copyWith(
        tags: mergeCustomTags(v.tags, [
          for (final pick in picks)
            CustomFormTag.fromCard(pick.card, pick.quantity),
        ]).take(customMaxTags).toList(),
      ),
    );
  }

  void _setTag(int index, CustomFormTag? next) {
    _update((v) {
      final tags = [...v.tags];
      if (next == null) {
        tags.removeAt(index);
        return v.copyWith(tags: tags);
      }
      tags[index] = next;
      // A condition change can make two rows the same card in the same
      // condition: they become one, as web's `mergeTags([], …)` does.
      return v.copyWith(tags: mergeCustomTags(const [], tags));
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final busy = _saving != null || _uploading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing custom'),
        actions: [
          if (value != null && !_isLive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: busy ? null : () => _save(publish: false),
                child: _saving == _Saving.draft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan draft'),
              ),
            ),
        ],
      ),
      body: _body(value),
      bottomNavigationBar: value == null
          ? null
          : _PublishBar(
              label: _isLive ? 'Simpan perubahan' : 'Pasang listing',
              saving: _saving == _Saving.publish,
              enabled: !busy,
              onPressed: () => _save(publish: true),
            ),
    );
  }

  Widget _body(CustomListingFormValue? value) {
    if (_notFound) {
      return const EmptyState(
        icon: LucideIcons.packageOpen,
        title: 'Listing tidak ditemukan',
        description: 'Listing ini mungkin sudah dihapus.',
      );
    }
    if (_loadError != null) {
      return EmptyState(
        icon: LucideIcons.circleAlert,
        title: 'Gagal memuat listing',
        description: userFacingError(_loadError!),
        action: OutlinedButton(
          onPressed: _load,
          child: const Text('Coba lagi'),
        ),
      );
    }
    if (value == null) return const AppLoader();

    final colors = context.appColors;
    final titleError = _showErrors ? customTitleError(value.title) : null;
    final titleLength = value.title.trim().runes.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        CustomPhotoGrid(
          urls: value.photoUrls,
          onChanged: (update) =>
              _update((v) => v.copyWith(photoUrls: update(v.photoUrls))),
          onUploadingChanged: (uploading) =>
              setState(() => _uploading = uploading),
        ),
        if (_showErrors && value.photoUrls.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Tambahkan minimal 1 foto.',
            style: AppTypography.caption(colors.error),
          ),
        ],
        const SizedBox(height: 20),
        _FieldLabel(
          label: 'Judul listing',
          hint: '$titleLength/$customTitleMax',
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _title,
          maxLength: customTitleMax,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (title) => _update((v) => v.copyWith(title: title)),
          decoration: InputDecoration(
            hintText: 'Contoh: Paket Charizard & Pikachu',
            errorText: titleError,
            // The count is in the label row, as on web.
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(label: 'Deskripsi', hint: 'Opsional'),
        const SizedBox(height: 6),
        TextField(
          controller: _description,
          maxLength: customDescriptionMax,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (description) =>
              _update((v) => v.copyWith(description: description)),
          decoration: const InputDecoration(
            hintText: 'Isi paket, kondisi, catatan pengiriman...',
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel(label: 'Harga'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [_RupiahInputFormatter()],
                    onChanged: (text) {
                      final digits = _digitsOf(text);
                      _update(
                        (v) => v.copyWith(
                          price: () => digits <= 0
                              ? null
                              : digits.clamp(1, customPriceMax),
                        ),
                      );
                    },
                    decoration: InputDecoration(
                      hintText: 'Rp0',
                      errorText: _showErrors && value.price == null
                          ? 'Isi harga dulu.'
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel(label: 'Stok'),
                const SizedBox(height: 6),
                _Stepper(
                  value: value.quantity,
                  // Copies in buyers' checkouts can't be taken back.
                  min: value.qtyLocked < 1 ? 1 : value.qtyLocked,
                  max: customMaxQuantity,
                  onChanged: (q) => _update((v) => v.copyWith(quantity: q)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _FieldLabel(
          label: 'Kartu di listing ini',
          hint: value.tags.isEmpty ? 'Opsional' : null,
        ),
        const SizedBox(height: 6),
        if (value.tags.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: _tagCards,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Tag kartu dari katalog'),
            ),
          )
        else ...[
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                for (final (i, tag) in value.tags.indexed) ...[
                  if (i > 0) Divider(height: 1, color: context.borderColor),
                  _TagRow(
                    key: ValueKey('${tag.cardId}:${tag.condition.raw}'),
                    tag: tag,
                    onChanged: (next) => _setTag(i, next),
                    onRemove: () => _setTag(i, null),
                  ),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: value.tags.length >= customMaxTags ? null : _tagCards,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Tag kartu lain'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 14),
        _ToggleRow(
          label: 'Terima penawaran',
          description:
              'Pembeli bisa menawar harga. Kamu yang putuskan terima atau '
              'tolak.',
          value: value.acceptsOffers,
          onChanged: (v) => _update((f) => f.copyWith(acceptsOffers: v)),
        ),
        const SizedBox(height: 14),
        _ToggleRow(
          label: 'Perpanjang otomatis',
          description: 'Kalau mati, listing kedaluwarsa setelah 30 hari.',
          value: value.autoRelist,
          onChanged: (v) => _update((f) => f.copyWith(autoRelist: v)),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: AppTypography.bodySmSemibold(context.appColors.onSurface),
    );
    // Bare when there is no hint: "Stok" sits in a column only as wide as
    // its stepper, where a row reaching for the hint's side has no width
    // to reach into.
    if (hint == null) return text;
    return Row(
      children: [
        Expanded(child: text),
        Text(hint!, style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.bodySmSemibold(
                  context.appColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SellerSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// One tagged card: its art, print and condition, and how many copies.
/// Taking it to zero takes the card off.
class _TagRow extends StatelessWidget {
  const _TagRow({
    super.key,
    required this.tag,
    required this.onChanged,
    required this.onRemove,
  });

  final CustomFormTag tag;
  final ValueChanged<CustomFormTag> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: CardArt(
              imageUrl: proxyImageUrl(tag.imageUrl),
              borderRadius: AppRadius.sm,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CardLanguageBadge(language: tag.language, size: 14),
                    if (tag.expansionCode.isNotEmpty)
                      _CodeBadge(code: tag.expansionCode),
                    if (tag.number.isNotEmpty)
                      Text(
                        tag.number,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    _ConditionMenu(
                      condition: tag.condition,
                      onChanged: (c) => onChanged(tag.copyWith(condition: c)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Stepper(
            value: tag.quantity,
            min: 0,
            max: customMaxQuantity,
            dense: true,
            onChanged: (q) =>
                q == 0 ? onRemove() : onChanged(tag.copyWith(quantity: q)),
          ),
        ],
      ),
    );
  }
}

/// Web's set-code tag: white on the brand black.
class _CodeBadge extends StatelessWidget {
  const _CodeBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.onSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        code.toUpperCase(),
        style: AppTypography.badge(colors.surface),
      ),
    );
  }
}

/// The tag's grade, and a menu to change it. DMG is collection-only and the
/// legacy PSA grades are not offered for new tags, as on drafts.
class _ConditionMenu extends StatelessWidget {
  const _ConditionMenu({required this.condition, required this.onChanged});

  final CardCondition condition;
  final ValueChanged<CardCondition> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CardCondition>(
      initialValue: condition,
      tooltip: 'Ubah kondisi',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final c in CardCondition.values)
          if ((!c.isLegacy && !c.isCollectionOnly) || c == condition)
            PopupMenuItem(value: c, child: Text(c.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.mutedForeground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              condition.short,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronDown,
              size: 13,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.dense = false,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 28.0 : 40.0;
    Widget button(IconData icon, String label, int? next) => SizedBox(
      width: size,
      height: size,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: label,
        icon: Icon(icon, size: dense ? 14 : 16),
        onPressed: next == null ? null : () => onChanged(next),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(LucideIcons.minus, 'Kurangi', value > min ? value - 1 : null),
          SizedBox(
            width: dense ? 24 : 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ),
          button(LucideIcons.plus, 'Tambah', value < max ? value + 1 : null),
        ],
      ),
    );
  }
}

/// Pinned under the form, as web's mobile footer is: the one way to publish
/// is always in reach.
class _PublishBar extends StatelessWidget {
  const _PublishBar({
    required this.label,
    required this.saving,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool saving;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.appSemantic.success,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      const SizedBox(width: 6),
                      const Icon(LucideIcons.arrowRight, size: 16),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

int _digitsOf(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// "Rp1.250.000" as it is typed, like the draft card's price.
class _RupiahInputFormatter extends TextInputFormatter {
  const _RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digitsOf(newValue.text);
    if (digits <= 0) return const TextEditingValue();
    final text = formatRupiah(digits.clamp(1, customPriceMax));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
