import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/address_repository.dart';
import '../../repository/models/address_model.dart';
import '../../usecase/address_notifier.dart';

/// Opens the add/edit address form. Resolves true when an address was
/// saved.
Future<bool?> showAddressFormSheet(
  BuildContext context, {
  AddressModel? address,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _AddressFormSheet(address: address),
  );
}

/// Ports the web address form's fields and its cascading
/// province → kota/kabupaten → kecamatan pickers, resolved from the bundled
/// dataset so the stored region names match what the server writes.
class _AddressFormSheet extends ConsumerStatefulWidget {
  const _AddressFormSheet({this.address});

  final AddressModel? address;

  @override
  ConsumerState<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends ConsumerState<_AddressFormSheet> {
  late final TextEditingController _label;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _fullAddress;
  late final TextEditingController _postalCode;
  late final TextEditingController _notes;

  AreaOption? _province;
  AreaOption? _city;
  AreaOption? _district;
  bool _makePrimary = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.address != null;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    _label = TextEditingController(text: address?.label ?? '');
    _contactName = TextEditingController(text: address?.contactName ?? '');
    _contactPhone = TextEditingController(text: address?.contactPhone ?? '');
    _fullAddress = TextEditingController(text: address?.fullAddress ?? '');
    _postalCode = TextEditingController(text: address?.postalCode ?? '');
    _notes = TextEditingController(text: address?.notes ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _label,
      _contactName,
      _contactPhone,
      _fullAddress,
      _postalCode,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Seeds the pickers from the address being edited, once the dataset is
  /// available to resolve its stored codes.
  void _seedAreas(AreaCatalog catalog) {
    final address = widget.address;
    if (address == null || _province != null) return;
    _province = catalog.findProvince(address.provinceId);
    _city = catalog.findRegency(address.cityId);
    _district = catalog.findDistrict(address.districtId);
  }

  Future<void> _save() async {
    final province = _province;
    final city = _city;
    final district = _district;

    if (_label.text.trim().isEmpty ||
        _contactName.text.trim().isEmpty ||
        _contactPhone.text.trim().length < 8 ||
        _fullAddress.text.trim().isEmpty) {
      setState(() => _error = 'Lengkapi label, nama, nomor HP, dan alamat.');
      return;
    }
    if (province == null || city == null || district == null) {
      setState(() => _error = 'Pilih provinsi, kota/kabupaten, dan kecamatan.');
      return;
    }
    final postal = _postalCode.text.trim();
    if (postal.isNotEmpty && !RegExp(r'^[0-9]{5}$').hasMatch(postal)) {
      setState(() => _error = 'Kode pos harus 5 angka.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = ref.read(addressRepositoryProvider);
    final notes = _notes.text.trim();
    final error = _isEdit
        ? await repository.updateAddress(
            id: widget.address!.id,
            label: _label.text.trim(),
            contactName: _contactName.text.trim(),
            contactPhone: _contactPhone.text.trim(),
            province: province,
            city: city,
            district: district,
            fullAddress: _fullAddress.text.trim(),
            postalCode: postal.isEmpty ? null : postal,
            notes: notes.isEmpty ? null : notes,
          )
        : await repository.createAddress(
            label: _label.text.trim(),
            contactName: _contactName.text.trim(),
            contactPhone: _contactPhone.text.trim(),
            province: province,
            city: city,
            district: district,
            fullAddress: _fullAddress.text.trim(),
            postalCode: postal.isEmpty ? null : postal,
            notes: notes.isEmpty ? null : notes,
            makePrimary: _makePrimary,
          );

    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.invalidate(addressesProvider);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Alamat diperbarui' : 'Alamat disimpan')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catalogAsync = ref.watch(areaCatalogProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEdit ? 'Ubah Alamat' : 'Tambah Alamat',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Rumah, Kantor, ...',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactName,
              decoration: const InputDecoration(labelText: 'Nama penerima'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Nomor HP'),
            ),
            const SizedBox(height: 12),
            catalogAsync.when(
              data: (catalog) {
                _seedAreas(catalog);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AreaField(
                      label: 'Provinsi',
                      value: _province,
                      options: catalog.provinces,
                      onSelected: (option) => setState(() {
                        _province = option;
                        _city = null;
                        _district = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _AreaField(
                      label: 'Kota / Kabupaten',
                      value: _city,
                      enabled: _province != null,
                      options: _province == null
                          ? const []
                          : catalog.regenciesOf(_province!.code),
                      onSelected: (option) => setState(() {
                        _city = option;
                        _district = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _AreaField(
                      label: 'Kecamatan',
                      value: _district,
                      enabled: _city != null,
                      options: _city == null
                          ? const []
                          : catalog.districtsOf(_city!.code),
                      onSelected: (option) => setState(() => _district = option),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Text(
                'Gagal memuat daftar wilayah.',
                style: AppTypography.bodySm(colors.error),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _postalCode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: const InputDecoration(
                labelText: 'Kode pos (opsional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullAddress,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Alamat lengkap',
                hintText: 'Nama jalan, nomor rumah, RT/RW, patokan',
              ),
            ),
            TextField(
              controller: _notes,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Catatan kurir (opsional)',
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _makePrimary,
                onChanged: (value) =>
                    setState(() => _makePrimary = value ?? false),
                title: Text(
                  'Jadikan alamat utama',
                  style: AppTypography.bodySm(colors.onSurface),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: AppTypography.bodySm(colors.error)),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEdit ? 'Simpan Perubahan' : 'Simpan Alamat'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cascading picker. Opens a searchable list — the district level has
/// ~7,000 entries, so search isn't optional.
class _AreaField extends StatelessWidget {
  const _AreaField({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final AreaOption? value;
  final List<AreaOption> options;
  final ValueChanged<AreaOption> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showModalBottomSheet<AreaOption>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Theme.of(context).cardColor,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                ),
                builder: (_) => _AreaPicker(title: label, options: options),
              );
              if (picked != null) onSelected(picked);
            }
          : null,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
        child: Text(
          value?.name ?? 'Pilih $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(
            value == null ? context.mutedForeground : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _AreaPicker extends StatefulWidget {
  const _AreaPicker({required this.title, required this.options});

  final String title;
  final List<AreaOption> options;

  @override
  State<_AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<_AreaPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.name.toLowerCase().contains(query))
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: AppTypography.h3(context.appColors.onSurface),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Cari...',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    filtered[i].name,
                    style: AppTypography.bodySm(context.appColors.onSurface),
                  ),
                  onTap: () => Navigator.of(context).pop(filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
