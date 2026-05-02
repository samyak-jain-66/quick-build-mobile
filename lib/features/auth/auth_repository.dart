import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class OtpVerifyResult {
  const OtpVerifyResult({
    required this.refreshToken,
    required this.accessToken,
    this.userId,
  });

  final String refreshToken;
  final String accessToken;
  final String? userId;
}

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  /// Asks the backend to send a Twilio Verify SMS to `phone`.
  Future<void> sendOtp(String phone) async {
    await _dio.post<Map<String, dynamic>>(
      '/auth/otp/send',
      data: {'phone': phone},
    );
  }

  /// Validates the user-entered code with the backend, which talks to
  /// Twilio and (on approval) returns a real Supabase session that the
  /// caller installs via `Supabase.auth.setSession(refreshToken)`.
  Future<OtpVerifyResult> verifyOtp(String phone, String code) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {'phone': phone, 'code': code},
    );
    final data = res.data ?? const <String, dynamic>{};
    final refresh = data['refresh_token'] as String?;
    final access = data['access_token'] as String?;
    if (refresh == null || access == null) {
      throw Exception('OTP verify did not return tokens');
    }
    return OtpVerifyResult(
      refreshToken: refresh,
      accessToken: access,
      userId: data['user_id'] as String?,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
