import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/app_theme.dart';

/// Result returned by [AddressMapPicker]. The address parts are filled
/// in best-effort by reverse-geocoding the picked coordinates; any of
/// them may be null when the geocoder fails or the field is missing.
class PickedLocation {
  const PickedLocation({
    required this.lat,
    required this.lng,
    this.line1,
    this.city,
    this.state,
    this.pincode,
  });

  final double lat;
  final double lng;
  final String? line1;
  final String? city;
  final String? state;
  final String? pincode;
}

/// Full-screen Google Map picker. The pin is fixed in the centre of the
/// viewport; the user drags the map underneath it. We reverse-geocode
/// on each `onCameraIdle` so the surfaced address text updates as they
/// fine-tune. Bottom CTA returns a [PickedLocation] to the caller.
class AddressMapPicker extends StatefulWidget {
  const AddressMapPicker({super.key, this.initialLat, this.initialLng});

  /// Optional seed - useful for re-opening the picker after the user
  /// already picked once, or for the Edit-address flow later. When
  /// either value is null we ask Geolocator for the current device
  /// position instead.
  final double? initialLat;
  final double? initialLng;

  @override
  State<AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<AddressMapPicker> {
  GoogleMapController? _controller;
  // Default fallback (centre of India-ish) until we know better - the
  // GoogleMap widget needs *some* initial target.
  static const _kFallback = LatLng(28.6139, 77.2090);

  LatLng _center = _kFallback;
  Placemark? _placemark;
  bool _loadingInitial = true;
  bool _resolvingPlace = false;
  String? _permissionError;
  Timer? _idleDebounce;

  @override
  void initState() {
    super.initState();
    _seedInitialLocation();
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _seedInitialLocation() async {
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (lat != null && lng != null) {
      final initial = LatLng(lat, lng);
      setState(() {
        _center = initial;
        _loadingInitial = false;
      });
      _resolvePlacemark(initial);
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _permissionError = 'Location permission denied. '
              'You can still drag the map to pick a spot.';
          _loadingInitial = false;
        });
        return;
      }
      // Last-known is instant; current is a couple of seconds. Prefer
      // last-known so the map snaps into place, then upgrade if it
      // returns null. Same defensive pattern we use elsewhere in the
      // app for emulator compatibility.
      Position? position = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      );
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 10),
      );
      final ll = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _center = ll;
        _loadingInitial = false;
      });
      // If the controller is already up (race-free initState) move it.
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(ll, 17));
      _resolvePlacemark(ll);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionError =
            'Could not read your location. Drag the map to pick a spot.';
        _loadingInitial = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingInitial = true);
    await _seedInitialLocation();
  }

  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
  }

  void _onCameraIdle() {
    // Debounce so we don't spam the geocoder while the user is panning.
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 350), () {
      _resolvePlacemark(_center);
    });
  }

  Future<void> _resolvePlacemark(LatLng ll) async {
    if (!mounted) return;
    setState(() => _resolvingPlace = true);
    try {
      final results = await placemarkFromCoordinates(ll.latitude, ll.longitude);
      if (!mounted) return;
      setState(() {
        _placemark = results.isNotEmpty ? results.first : null;
        _resolvingPlace = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _placemark = null;
        _resolvingPlace = false;
      });
    }
  }

  void _confirm() {
    final p = _placemark;
    final picked = PickedLocation(
      lat: _center.latitude,
      lng: _center.longitude,
      line1: _firstNonEmpty([
        p?.subThoroughfare,
        p?.thoroughfare,
        p?.subLocality,
      ]),
      city: _firstNonEmpty([p?.locality, p?.subAdministrativeArea]),
      state: p?.administrativeArea?.trim().isNotEmpty == true
          ? p!.administrativeArea
          : null,
      pincode: p?.postalCode?.trim().isNotEmpty == true ? p!.postalCode : null,
    );
    Navigator.of(context).pop(picked);
  }

  String? _firstNonEmpty(List<String?> parts) {
    for (final p in parts) {
      if (p != null && p.trim().isNotEmpty) return p.trim();
    }
    return null;
  }

  String _addressLines() {
    final p = _placemark;
    if (p == null) {
      return '${_center.latitude.toStringAsFixed(5)}, '
          '${_center.longitude.toStringAsFixed(5)}';
    }
    final parts = <String>[
      _firstNonEmpty([p.subThoroughfare, p.thoroughfare, p.subLocality]) ?? '',
      _firstNonEmpty([p.locality, p.subAdministrativeArea]) ?? '',
      p.postalCode ?? '',
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick location')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 17),
            onMapCreated: (c) {
              _controller = c;
              if (!_loadingInitial) {
                c.animateCamera(CameraUpdate.newLatLngZoom(_center, 17));
              }
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Fixed pin overlay - the pin tip ought to land on the centre
          // of the map. We offset upward by ~half the icon height so the
          // tip points exactly at _center.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Icon(
                  Icons.location_pin,
                  size: 44,
                  color: AppColors.primary,
                  shadows: const [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loadingInitial)
            const Center(child: CircularProgressIndicator()),
          // Use-current-location FAB stacked above the bottom card.
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton.small(
              heroTag: 'use-current',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: _loadingInitial ? null : _useCurrentLocation,
              child: const Icon(Icons.my_location_outlined),
            ),
          ),
          // Bottom address sheet + Confirm CTA.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.surface,
              elevation: 8,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected location',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_resolvingPlace)
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          _addressLines(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      if (_permissionError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _permissionError!,
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loadingInitial ? null : _confirm,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Confirm location'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
