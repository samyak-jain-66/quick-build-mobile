import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env/app_env.dart';
import '../../theme/app_theme.dart';
import 'address_map_picker.dart';
import 'addresses_repository.dart';

// Indian-locale validation regexes. Phones are 10 digits starting 6-9
// (Trai mobile range), pincodes are 6 digits with the first non-zero so
// "012345" et al are rejected.
final _kPhoneRegex = RegExp(r'^[6-9]\d{9}$');
final _kPincodeRegex = RegExp(r'^[1-9]\d{5}$');
final _kNameRegex = RegExp(r"^[A-Za-z][A-Za-z .']{1,49}$");
final _kCityStateRegex = RegExp(r'^[A-Za-z][A-Za-z .]{1,39}$');

String? _required(String? v, String label) {
  if (v == null || v.trim().isEmpty) return '$label is required';
  return null;
}

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addrsAsync = ref.watch(addressesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
      body: addrsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (addrs) {
          if (addrs.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(addressesProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: addrs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = addrs[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.outline),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(a.label ?? 'Address',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                          const SizedBox(width: 8),
                          if (a.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                              child: const Text(
                                'DEFAULT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ref
                                  .read(addressesRepositoryProvider)
                                  .delete(a.id);
                              ref.invalidate(addressesProvider);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(a.line1,
                          style: const TextStyle(fontSize: 14)),
                      Text('${a.city}, ${a.state} ${a.pincode}',
                          style:
                              const TextStyle(color: AppColors.textMuted)),
                      if (a.recipientName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${a.recipientName} \u2022 ${a.recipientPhone ?? ''}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressForm(
        onSaved: () {
          ref.invalidate(addressesProvider);
        },
      ),
    );
  }
}

class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _isDefault = false;
  bool _saving = false;
  double? _lat;
  double? _lng;
  // Flips on first Save tap so the map-pin error only shows after the
  // user has actually tried to submit (matches Form's onUserInteraction
  // autovalidate behaviour).
  bool _mapTouched = false;

  @override
  void dispose() {
    for (final c in [_label, _line1, _city, _state, _pincode, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => AddressMapPicker(
          initialLat: _lat,
          initialLng: _lng,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.lat;
      _lng = picked.lng;
      if (_line1.text.isEmpty && picked.line1 != null) {
        _line1.text = picked.line1!;
      }
      if (_city.text.isEmpty && picked.city != null) {
        _city.text = picked.city!;
      }
      if (_state.text.isEmpty && picked.state != null) {
        _state.text = picked.state!;
      }
      if (_pincode.text.isEmpty && picked.pincode != null) {
        _pincode.text = picked.pincode!;
      }
    });
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final mapOk = _lat != null && _lng != null;
    if (!_mapTouched) setState(() => _mapTouched = true);
    if (!formOk || !mapOk) {
      final msg = !formOk
          ? 'Please fix the highlighted fields'
          : 'Please pick your location on the map';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(addressesRepositoryProvider).create({
        'label': _label.text.trim(),
        'line1': _line1.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'recipient_name': _name.text.trim(),
        'recipient_phone': _phone.text.trim(),
        'is_default': _isDefault,
        'lat': _lat,
        'lng': _lng,
      });
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add new address',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 12),
              _PickLocationCard(
                lat: _lat,
                lng: _lng,
                onTap: _pickOnMap,
                showError: _mapTouched && (_lat == null || _lng == null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  hintText: 'Label (Home, Site...)*',
                ),
                maxLength: 32,
                validator: (v) {
                  final err = _required(v, 'Label');
                  if (err != null) return err;
                  if (v!.trim().length > 32) {
                    return 'Label must be 32 characters or fewer';
                  }
                  return null;
                },
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _line1,
                decoration: const InputDecoration(
                  hintText: 'Flat / Building / Street*',
                ),
                maxLength: 120,
                maxLines: 2,
                minLines: 1,
                validator: (v) {
                  final err = _required(v, 'Address');
                  if (err != null) return err;
                  final t = v!.trim();
                  if (t.length < 5) {
                    return 'Address must be at least 5 characters';
                  }
                  if (t.length > 120) {
                    return 'Address must be 120 characters or fewer';
                  }
                  return null;
                },
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(hintText: 'City*'),
                    maxLength: 40,
                    validator: (v) {
                      final err = _required(v, 'City');
                      if (err != null) return err;
                      final t = v!.trim();
                      if (t.length < 2) {
                        return 'City must be at least 2 letters';
                      }
                      if (!_kCityStateRegex.hasMatch(t)) {
                        return 'Use letters and spaces only';
                      }
                      return null;
                    },
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _state,
                    decoration: const InputDecoration(hintText: 'State*'),
                    maxLength: 40,
                    validator: (v) {
                      final err = _required(v, 'State');
                      if (err != null) return err;
                      final t = v!.trim();
                      if (t.length < 2) {
                        return 'State must be at least 2 letters';
                      }
                      if (!_kCityStateRegex.hasMatch(t)) {
                        return 'Use letters and spaces only';
                      }
                      return null;
                    },
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pincode,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  hintText: 'Pincode*',
                  counterText: '',
                ),
                validator: (v) {
                  final err = _required(v, 'Pincode');
                  if (err != null) return err;
                  if (!_kPincodeRegex.hasMatch(v!.trim())) {
                    return 'Pincode must be 6 digits starting 1-9';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(hintText: 'Recipient name*'),
                    maxLength: 50,
                    validator: (v) {
                      final err = _required(v, 'Recipient name');
                      if (err != null) return err;
                      final t = v!.trim();
                      if (t.length < 2) {
                        return 'Name must be at least 2 letters';
                      }
                      if (!_kNameRegex.hasMatch(t)) {
                        return "Use letters, spaces, ' and . only";
                      }
                      return null;
                    },
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Recipient phone*',
                      counterText: '',
                    ),
                    validator: (v) {
                      final err = _required(v, 'Phone');
                      if (err != null) return err;
                      if (!_kPhoneRegex.hasMatch(v!.trim())) {
                        return 'Phone must be 10 digits starting 6-9';
                      }
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                title: const Text('Set as default address'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : const Text('Save address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickLocationCard extends StatelessWidget {
  const _PickLocationCard({
    required this.lat,
    required this.lng,
    required this.onTap,
    this.showError = false,
  });

  final double? lat;
  final double? lng;
  final VoidCallback onTap;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final hasCoords = lat != null && lng != null;
    final ctaLabel = hasCoords ? 'Change location' : 'Pick on map';
    final borderColor =
        showError && !hasCoords ? AppColors.danger : AppColors.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 120,
                child: hasCoords
                    ? _StaticMapThumbnail(lat: lat!, lng: lng!)
                    : Container(
                        color: const Color(0xFFF5F5F5),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_outlined,
                                size: 32, color: AppColors.textMuted),
                            SizedBox(height: 4),
                            Text(
                              'Pin your exact delivery spot',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasCoords
                            ? 'Location pinned • '
                                '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                            : 'Helps the rider reach you faster',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.edit_location_alt_outlined,
                          size: 18),
                      label: Text(ctaLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showError && !hasCoords)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 12),
            child: Text(
              'Please pick your location on the map',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _StaticMapThumbnail extends StatelessWidget {
  const _StaticMapThumbnail({required this.lat, required this.lng});
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final key = AppEnv.googleMapsApiKey;
    if (key.isEmpty) {
      return Container(
        color: const Color(0xFFF5F5F5),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_pin,
                size: 28, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    final url =
        'https://maps.googleapis.com/maps/api/staticmap?center=$lat,$lng'
        '&zoom=16&size=600x180&scale=2'
        '&markers=color:red%7C$lat,$lng'
        '&key=$key';
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: const Color(0xFFF5F5F5),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFFF5F5F5),
        alignment: Alignment.center,
        child: const Icon(Icons.location_pin,
            size: 28, color: AppColors.primary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.location_off_outlined,
                size: 60, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text('No saved addresses',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text('Add a delivery address to place orders faster.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
