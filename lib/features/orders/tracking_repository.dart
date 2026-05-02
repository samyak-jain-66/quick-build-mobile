import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api/api_client.dart';

class RiderInfo {
  const RiderInfo({
    required this.name,
    required this.phone,
    this.id,
    this.photoUrl,
    this.rating = 5.0,
    this.ratingCount = 0,
  });

  /// Foreign key into `rider_details`. Null only for legacy shipments
  /// recorded before the rider_details migration landed.
  final String? id;
  final String name;
  final String phone;
  final String? photoUrl;
  final double rating;
  final int ratingCount;

  static RiderInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final n = json['name'] as String?;
    final p = json['phone'] as String?;
    if (n == null || p == null) return null;
    return RiderInfo(
      id: json['id'] as String?,
      name: n,
      phone: p,
      photoUrl: json['photo_url'] as String?,
      rating: ((json['rating'] as num?) ?? 5).toDouble(),
      ratingCount: ((json['rating_count'] as num?) ?? 0).toInt(),
    );
  }
}

class OrderTracking {
  const OrderTracking({
    required this.isExpress,
    required this.status,
    this.warehouse,
    this.destination,
    this.polyline,
    this.currentLocation,
    this.rider,
    this.etaMinutes,
    this.deliveredAt,
    this.feedbackSubmitted = false,
  });

  final bool isExpress;
  final String status;
  final LatLng? warehouse;
  final LatLng? destination;
  final String? polyline;
  final LatLng? currentLocation;
  final RiderInfo? rider;
  final int? etaMinutes;
  final String? deliveredAt;
  final bool feedbackSubmitted;

  /// True while the order is active enough to show the live map. We no
  /// longer gate on `isExpress` - the map renders for every order until
  /// it's delivered or cancelled.
  bool get isLive => status != 'delivered' && status != 'cancelled';

  factory OrderTracking.fromJson(Map<String, dynamic> json) {
    LatLng? coord(dynamic raw) {
      if (raw is Map) {
        final lat = (raw['lat'] as num?)?.toDouble();
        final lng = (raw['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
      return null;
    }

    return OrderTracking(
      isExpress: json['is_express'] == true,
      status: (json['status'] as String?) ?? 'placed',
      warehouse: coord(json['warehouse']),
      destination: coord(json['destination']),
      polyline: json['polyline'] as String?,
      currentLocation: coord(json['current_location']),
      rider: RiderInfo.fromJson(
        (json['rider'] as Map?)?.cast<String, dynamic>(),
      ),
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      deliveredAt: json['delivered_at'] as String?,
      feedbackSubmitted: json['feedback_submitted'] == true,
    );
  }
}

class TrackingRepository {
  TrackingRepository(this._dio);
  final Dio _dio;

  Future<OrderTracking> get(String orderId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/orders/$orderId/tracking',
    );
    return OrderTracking.fromJson(res.data ?? const {});
  }
}

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingRepository(ref.watch(apiClientProvider)),
);

final orderTrackingProvider = FutureProvider.family
    .autoDispose<OrderTracking, String>((ref, orderId) async {
  return ref.watch(trackingRepositoryProvider).get(orderId);
});

/// Decodes a Google encoded polyline into a list of LatLng points.
/// Mirror of the backend decoder in google-maps.service.ts so we can draw
/// the route without pulling another package in.
List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0;
  int lat = 0;
  int lng = 0;
  while (index < encoded.length) {
    int result = 0;
    int shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    result = 0;
    shift = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
