import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'location_models.dart';

class ServiceabilityRepository {
  ServiceabilityRepository(this._dio);
  final Dio _dio;

  /// Asks the backend whether [pincode] is currently serviceable. Returns a
  /// [ServiceableLocation] with the canonical city name when serviceable,
  /// or with `isServiceable: false` and `city: null` otherwise.
  Future<ServiceableLocation> check(String pincode) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/serviceability/check',
      queryParameters: {'pincode': pincode},
    );
    final data = res.data ?? const <String, dynamic>{};
    return ServiceableLocation(
      pincode: (data['pincode'] as String?) ?? pincode,
      city: data['city'] as String?,
      isServiceable: (data['serviceable'] as bool?) ?? false,
    );
  }

  /// Registers interest for a pincode we don't serve yet. The backend
  /// upserts on `(pincode, email)` so repeated submissions are idempotent.
  Future<void> joinWaitlist({
    required String pincode,
    required String name,
    required String phone,
    required String email,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/waitlist',
      data: {
        'pincode': pincode,
        'name': name,
        'phone': phone,
        'email': email,
      },
    );
  }
}

final serviceabilityRepositoryProvider = Provider<ServiceabilityRepository>(
  (ref) => ServiceabilityRepository(ref.watch(apiClientProvider)),
);
