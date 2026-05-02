import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class CouponSummary {
  CouponSummary({
    required this.code,
    required this.description,
    required this.type,
    required this.value,
    required this.minOrderAmount,
    required this.maxDiscount,
    required this.endsAt,
  });

  final String code;
  final String? description;

  /// 'flat' | 'percent'
  final String type;
  final double value;
  final double minOrderAmount;
  final double? maxDiscount;
  final DateTime? endsAt;

  factory CouponSummary.fromJson(Map<String, dynamic> json) => CouponSummary(
        code: json['code'] as String,
        description: json['description'] as String?,
        type: (json['type'] as String?) ?? 'flat',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        minOrderAmount: (json['min_order_amount'] as num?)?.toDouble() ?? 0,
        maxDiscount: (json['max_discount'] as num?)?.toDouble(),
        endsAt: json['ends_at'] != null
            ? DateTime.tryParse(json['ends_at'] as String)
            : null,
      );
}

class CouponValidationResult {
  const CouponValidationResult({
    required this.discount,
    required this.description,
  });
  final double discount;
  final String description;
}

class CouponsRepository {
  CouponsRepository(this._dio);
  final Dio _dio;

  Future<List<CouponSummary>> featured() async {
    final res = await _dio.get<List<dynamic>>('/coupons');
    return (res.data ?? const [])
        .map((e) => CouponSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CouponValidationResult> validate({
    required String code,
    required double subtotal,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/coupons/validate',
      data: {'code': code, 'subtotal': subtotal},
    );
    final d = res.data!;
    return CouponValidationResult(
      discount: (d['discount'] as num?)?.toDouble() ?? 0,
      description: (d['description'] as String?) ?? '',
    );
  }
}

final couponsRepositoryProvider = Provider<CouponsRepository>(
  (ref) => CouponsRepository(ref.watch(apiClientProvider)),
);

final featuredCouponsProvider = FutureProvider<List<CouponSummary>>(
  (ref) => ref.watch(couponsRepositoryProvider).featured(),
);
