import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../../features/auth/auth_repository.dart';
import '../env/app_env.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

final currentSessionProvider = Provider<Session?>((ref) {
  final changes = ref.watch(authStateChangesProvider);
  return changes.maybeWhen(
    data: (state) => state.session,
    orElse: () => Supabase.instance.client.auth.currentSession,
  );
});

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider) != null;
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  SupabaseClient get _sb => _ref.read(supabaseClientProvider);

  /// Phone OTP via Twilio Verify (called server-side by our API). The
  /// backend triggers the SMS; nothing happens client-side beyond the
  /// HTTP POST. State flips back to data on success so the OTP screen
  /// transitions out of the loading spinner.
  Future<void> sendOtp(String phone) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(authRepositoryProvider).sendOtp(phone);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sends the user-entered code to the API. On success the API returns
  /// a real Supabase session - we install it via `setSession` and the
  /// existing auth-state listeners route the user into the app.
  Future<void> verifyOtp(String phone, String code) async {
    state = const AsyncValue.loading();
    try {
      final r = await _ref.read(authRepositoryProvider).verifyOtp(phone, code);
      await _sb.auth.setSession(r.refreshToken);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Native Google Sign-In + Supabase ID-token exchange. Requires:
  /// - `GOOGLE_WEB_CLIENT_ID` to be passed via --dart-define (the Web OAuth
  ///   client ID auto-created by the Firebase project).
  /// - The Android signing-key SHA-1 to be registered with the Firebase
  ///   project (otherwise `googleAuth.idToken` comes back null).
  /// - The Google provider enabled in the Supabase Auth dashboard with
  ///   the same Web client ID + secret.
  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      if (AppEnv.googleWebClientId.isEmpty) {
        throw Exception(
          'Google sign-in is not configured. Pass '
          '--dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com',
        );
      }
      // iOS: GIDSignIn's id_token always carries a nonce we can't read back,
      // so signInWithIdToken returns 400 from Supabase. Use the browser-
      // based OAuth flow instead - the redirect comes back via the existing
      // quickbuild:// deep link and Supabase.initialize's listener finishes
      // the session exchange.
      if (Platform.isIOS) {
        // External Safari is required for the quickbuild:// redirect to
        // hand control back to the app. SFSafariViewController (the
        // platform default) is sandboxed and silently drops the
        // custom-scheme redirect.
        final ok = await _sb.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'quickbuild://login-callback',
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
        if (!ok) {
          throw Exception('Could not open the Google sign-in page.');
        }
        state = const AsyncValue.data(null);
        return;
      }
      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS ? AppEnv.googleIosClientId : null,
        serverClientId: AppEnv.googleWebClientId,
        scopes: const ['email', 'openid', 'profile'],
      );
      // Drop any cached account so the chooser always reappears - cleaner
      // UX and avoids stale id tokens after a recent sign-out.
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the chooser - no error, just bail.
        state = const AsyncValue.data(null);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception(
          'Google did not return an ID token. Most likely the Android '
          "signing-key SHA-1 isn't registered with the Firebase project.",
        );
      }
      await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    // Best-effort: forget the cached Google account so the next sign-in
    // shows the picker. Any error here is non-fatal (user may not have
    // signed in via Google in the first place).
    try {
      await GoogleSignIn().signOut();
    } catch (_) {/* swallow */}
    await _sb.auth.signOut();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>(
  (ref) => AuthController(ref),
);
