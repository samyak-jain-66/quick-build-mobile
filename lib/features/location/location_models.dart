/// Represents a pincode the user has chosen as their delivery location and
/// whether Quick-Build currently operates there. Cached verbatim in Hive so
/// the home screen can gate the feed at startup without a network round
/// trip, and re-validated whenever the user changes the location.
class ServiceableLocation {
  const ServiceableLocation({
    required this.pincode,
    required this.city,
    required this.isServiceable,
  });

  final String pincode;
  final String? city;
  final bool isServiceable;

  Map<String, dynamic> toJson() => {
        'pincode': pincode,
        'city': city,
        'is_serviceable': isServiceable,
      };

  factory ServiceableLocation.fromJson(Map<String, dynamic> json) =>
      ServiceableLocation(
        pincode: json['pincode'] as String,
        city: json['city'] as String?,
        isServiceable: (json['is_serviceable'] as bool?) ?? false,
      );
}

/// Typed failures surfaced by the LocationController so the picker sheet
/// can show nicely worded inline errors instead of a raw exception toast.
enum LocationFailureKind {
  permissionDenied,
  permissionPermanentlyDenied,
  servicesDisabled,
  noPostalCode,
  network,
  invalidPincode,
  unknown,
}

class LocationFailure implements Exception {
  const LocationFailure(this.kind, this.message);
  final LocationFailureKind kind;
  final String message;

  @override
  String toString() => 'LocationFailure(${kind.name}): $message';
}
