class AppEnv {
  const AppEnv._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://quick-build-backend.onrender.com/api',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://raomkerdxqwikpppnika.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhb21rZXJkeHF3aWtwcHBuaWthIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTIzNzQsImV4cCI6MjA5MjU4ODM3NH0.A_wjmmmGYCV0eLyWosWktrMHUOaXZbp-t0bt5u7EmHo',
  );

  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyApgJd_IS-z0xUM103CIdCCHZWHd9Bz6O4',
  );

  static const razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_test_ShLESvGcbdl1yj',
  );

  /// Web OAuth client ID from the Firebase / Google Cloud project. Used as
  /// `GoogleSignIn.serverClientId` so the resulting ID token is meant for
  /// Supabase, which expects the Google provider's web client audience.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '820520818404-ldj61fqa7sugcslqv593q5ubocbghk7r.apps.googleusercontent.com',
  );

  /// iOS-typed OAuth client ID (Application type: iOS in Google Cloud
  /// Console). Required by GIDSignIn on iOS - native code reads it from
  /// Info.plist (GIDClientID) and we also pass it to the Dart
  /// GoogleSignIn(clientId:) constructor for plugin-version safety.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '820520818404-ms3jomuub5nk5kkmjfm3tu9dj7kkv8jd.apps.googleusercontent.com',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
