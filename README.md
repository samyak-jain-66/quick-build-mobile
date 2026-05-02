# quick-build-mobile

Flutter customer app for the **Quick-Build** quick-commerce construction
platform — yellow/black industrial theme, 10 screens covering splash, OTP
login, home, categories, search, product, cart, checkout, order tracking and
profile.

> The NestJS backend lives in a sibling repo: **quick-build-backend**.
> The two repos are independent; the only runtime coupling is the
> `API_BASE_URL` `--dart-define` below pointing at wherever the backend is
> running.

## Stack

- Flutter 3.22+, Dart 3.3+
- Riverpod, go_router
- Dio for HTTP, Supabase Flutter SDK for auth + realtime
- google_maps_flutter, geolocator, geocoding
- razorpay_flutter
- Firebase (core, messaging, analytics) for push + analytics

## Prerequisites

- Flutter 3.22+ and Dart 3.3+
- Android Studio / Xcode toolchains for the platforms you target
- A running quick-build-backend (see that repo's README)
- A Google Maps API key (Android + iOS)
- A Razorpay test key id

## 1. Install dependencies

```bash
flutter pub get
```

## 2. Run the app

The app reads its config via `--dart-define` at run time. Values live in a
gitignored `.env.json` at the repo root; a thin `scripts/run.sh` wrapper
forwards them to Flutter via `--dart-define-from-file`.

```bash
cp .env.example.json .env.json   # then fill in values
scripts/run.sh                   # forwards args to `flutter run`
```

Examples:

```bash
scripts/run.sh                   # selected device
scripts/run.sh -d emulator-5554  # specific device
scripts/run.sh --release         # release run

# The same env file works for builds:
flutter build apk --dart-define-from-file=.env.json
flutter build appbundle --dart-define-from-file=.env.json
flutter build ios --dart-define-from-file=.env.json
```

Mobile-only keys live in `.env.json`:

- `API_BASE_URL`
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` (anon key only — RLS-gated)
- `RAZORPAY_KEY_ID` (publishable key id, no secret)
- `GOOGLE_MAPS_API_KEY`
- `GOOGLE_WEB_CLIENT_ID`

> Server-side secrets — `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`,
> `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT_JSON`,
> `MSG91_*`, `RESEND_*`, `WHATSAPP_*`, `TWILIO_*`, `REDIS_*`, `ADMIN_API_KEY`
> — belong in **quick-build-backend**'s env, not in this repo. They must
> never ship inside the APK/IPA.

`API_BASE_URL` host cheat-sheet:

| Environment             | Host                       |
|-------------------------|----------------------------|
| Android emulator        | `http://10.0.2.2:3000`     |
| iOS simulator           | `http://localhost:3000`    |
| Real device on same LAN | `http://<your-mac-LAN-ip>:3000` |

## 3. Native Google Maps key

Per platform, the Google Maps SDK needs the key wired in natively:

- **Android** — add to `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
  android:name="com.google.android.geo.API_KEY"
  android:value="YOUR_GOOGLE_MAPS_API_KEY" />
```

- **iOS** — in `ios/Runner/AppDelegate.swift`:

```swift
GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
```

## Screens (MVP)

1. **Splash** – session check
2. **Login** – phone OTP via Supabase Auth
3. **Home** – location pill, categories grid, express banner, top picks
4. **Categories** – hierarchical drill-down
5. **Search** – tsvector + trigram with facets + Redis-cached suggestions
6. **Product** – gallery, specs, bulk tiers, MOQ, vendor, reviews, similar/FBT
7. **Cart** – grouped by vendor, split-shipment preview, coupon, wallet
8. **Checkout** – address picker, GST invoice, payment method, Razorpay sheet
9. **Order tracking** – timeline + Google Map + Supabase Realtime channel
10. **Profile** – orders, addresses, wallet, RFQs, GST

## Common commands

```bash
flutter pub get          # install dependencies
flutter run              # run on the currently-selected device
flutter build apk        # release APK
flutter build appbundle  # Play Store bundle
flutter build ios        # iOS release build (run from macOS)
flutter analyze          # lint
flutter test             # tests
```
