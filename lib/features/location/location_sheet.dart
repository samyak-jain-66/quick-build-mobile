import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'location_controller.dart';
import 'location_models.dart';

/// Bottom sheet that lets the user detect their pincode via GPS or enter it
/// manually. Pops itself automatically on success. The caller doesn't need
/// a return value - consumers already watch [locationProvider] for state.
class LocationSheet extends ConsumerStatefulWidget {
  const LocationSheet({super.key});

  @override
  ConsumerState<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<LocationSheet> {
  final _pincodeCtrl = TextEditingController();
  bool _busyGps = false;
  bool _busyPincode = false;
  String? _gpsError;
  String? _pincodeError;

  @override
  void dispose() {
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _runGps() async {
    if (_busyGps || _busyPincode) return;
    setState(() {
      _busyGps = true;
      _gpsError = null;
      _pincodeError = null;
    });
    try {
      await ref
          .read(locationProvider.notifier)
          .useCurrentLocation();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _gpsError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gpsError = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busyGps = false);
    }
  }

  Future<void> _runPincode() async {
    if (_busyGps || _busyPincode) return;
    final code = _pincodeCtrl.text.trim();
    setState(() {
      _busyPincode = true;
      _gpsError = null;
      _pincodeError = null;
    });
    try {
      await ref.read(locationProvider.notifier).setByPincode(code);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _pincodeError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pincodeError = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busyPincode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.location_on_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Choose delivery location',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _GpsTile(
                busy: _busyGps,
                error: _gpsError,
                onTap: _runGps,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(child: Divider(color: AppColors.divider)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'or',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.divider)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your pincode',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pincodeCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            hintText: '122001',
                            counterText: '',
                            errorText: _pincodeError,
                          ),
                          onSubmitted: (_) => _runPincode(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _busyPincode ? null : _runPincode,
                          child: _busyPincode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Text('Check'),
                        ),
                      ),
                    ],
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

class _GpsTile extends StatelessWidget {
  const _GpsTile({
    required this.busy,
    required this.error,
    required this.onTap,
  });

  final bool busy;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            border: Border.all(
              color: AppColors.onPrimary.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.onPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Use my current location',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'We will detect your pincode via GPS',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.text,
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
