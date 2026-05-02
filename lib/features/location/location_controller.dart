import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'location_models.dart';
import 'serviceability_repository.dart';

/// Wraps the user's current delivery location. `null` means we have never
/// stored one (fresh install or the user cleared it); otherwise the cached
/// value comes straight from the Hive `app_settings` box keyed by
/// [_hiveKey]. Mutations always round-trip through the backend
/// serviceability check so we never trust a stale `isServiceable` flag.
class LocationController
    extends StateNotifier<AsyncValue<ServiceableLocation?>> {
  LocationController(this._ref)
      : super(const AsyncValue<ServiceableLocation?>.data(null)) {
    _hydrate();
  }

  static const _boxName = 'app_settings';
  static const _hiveKey = 'location_v1';

  final Ref _ref;

  ServiceabilityRepository get _repo =>
      _ref.read(serviceabilityRepositoryProvider);

  Box<String> get _box => Hive.box<String>(_boxName);

  Future<void> _hydrate() async {
    try {
      final raw = _box.get(_hiveKey);
      if (raw == null || raw.isEmpty) {
        state = const AsyncValue<ServiceableLocation?>.data(null);
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = AsyncValue<ServiceableLocation?>.data(
        ServiceableLocation.fromJson(decoded),
      );
    } catch (_) {
      // Corrupt cache - treat as fresh install.
      state = const AsyncValue<ServiceableLocation?>.data(null);
    }
  }

  Future<void> _persist(ServiceableLocation location) async {
    await _box.put(_hiveKey, jsonEncode(location.toJson()));
  }

  /// Validates [pincode] against the backend and stores the verdict.
  /// Throws [LocationFailure] on invalid input or network trouble so the UI
  /// can render a friendly inline message.
  Future<void> setByPincode(String pincode) async {
    final trimmed = pincode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      throw const LocationFailure(
        LocationFailureKind.invalidPincode,
        'Enter a valid 6-digit pincode.',
      );
    }
    try {
      final result = await _repo.check(trimmed);
      state = AsyncValue<ServiceableLocation?>.data(result);
      await _persist(result);
    } on DioException catch (e) {
      throw LocationFailure(
        LocationFailureKind.network,
        'Could not reach the server: ${e.message ?? e.type.name}',
      );
    } catch (e) {
      throw LocationFailure(
        LocationFailureKind.unknown,
        'Something went wrong: $e',
      );
    }
  }

  /// Requests OS location permission, resolves the device coordinates to a
  /// postal code and then validates it. Throws [LocationFailure] at each
  /// stage so the sheet can explain what went wrong.
  Future<void> useCurrentLocation() async {
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) {
      throw const LocationFailure(
        LocationFailureKind.servicesDisabled,
        'Turn on device location to detect your pincode.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureKind.permissionPermanentlyDenied,
        'Location access is blocked. Allow it in Settings to auto-detect.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        LocationFailureKind.permissionDenied,
        'Location permission was denied.',
      );
    }

    // Prefer the OS's cached fix - it's instant when the user was in the
    // app recently. Only fall back to an active read when there isn't one,
    // and keep that fallback short + low accuracy so the sheet doesn't
    // hang for 20s on Android emulators that don't emit a GPS fix at all.
    //
    // `forceAndroidLocationManager: true` bypasses Google's
    // FusedLocationProvider and reads the raw Android LocationManager
    // instead. This matters because a) the AVDs we test on are not
    // Google-Play images so the fused client is always empty, and b)
    // `adb emu geo fix` only feeds the LocationManager providers. On
    // real devices both paths are populated so the behaviour is
    // unchanged.
    Position? position = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: true,
    );
    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          forceAndroidLocationManager: true,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        throw const LocationFailure(
          LocationFailureKind.unknown,
          "Couldn't detect your location right now. "
              'Enter your pincode below instead.',
        );
      } catch (e) {
        throw LocationFailure(
          LocationFailureKind.unknown,
          "Couldn't read your location ($e). Try entering your pincode.",
        );
      }
    }

    final List<Placemark> placemarks;
    try {
      placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      throw LocationFailure(
        LocationFailureKind.noPostalCode,
        'Could not look up your address. ($e)',
      );
    }

    String? postal;
    for (final p in placemarks) {
      final pc = p.postalCode?.trim();
      if (pc != null && RegExp(r'^\d{6}$').hasMatch(pc)) {
        postal = pc;
        break;
      }
    }
    if (postal == null) {
      throw const LocationFailure(
        LocationFailureKind.noPostalCode,
        'We could not determine a pincode for your current location.',
      );
    }

    await setByPincode(postal);
  }

  /// Drops the cached location. The home screen will open the picker on the
  /// next frame.
  Future<void> clear() async {
    state = const AsyncValue<ServiceableLocation?>.data(null);
    await _box.delete(_hiveKey);
  }
}

final locationProvider = StateNotifierProvider<LocationController,
    AsyncValue<ServiceableLocation?>>(
  (ref) => LocationController(ref),
);
