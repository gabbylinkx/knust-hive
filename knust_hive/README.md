# KNUST Hive

Campus dashboard, feed, skills hub, and a live crowdsourced shuttle tracker
for KNUST students. Flutter + Riverpod + Supabase.

## Current app status
- Email/password sign-in with email confirmation and automatic profile setup;
  Google OAuth is an optional Supabase provider.
- Dashboard with live shuttle/ride counts, today's timetable, and a device-local
  to-do list. Timetable and CWA tools are also available under **More**.
- Shuttle tracker with a live OpenStreetMap view, operator GPS sharing, recent
  rider sightings, and ride board. Driver locations update in realtime while
  an approved operator keeps the app open and location permission enabled.
- Realtime campus feed with category filtering, student-owned post deletion,
  event RSVP and member reporting for moderator review.
- Curated external learning resources with per-student cloud progress.
- Group and one-to-one chat with realtime messages and creator-managed group
  membership. Student communities, mentorship requests, timetable, CWA
  calculator, marketplace, HTTPS past-question links, an emergency dialer
  shortcut, and a moderator report queue are available under **More**.
- The application still requires a configured Supabase project. Push
  notifications, portfolio pages, document uploads,
  and store signing/deployment are not configured.

## 1. Prerequisites
- Flutter 3.35+ (`flutter --version`)
- A free [Supabase](https://supabase.com) project
- (Optional, for push notifications) a Firebase project

## 2. Supabase setup
1. Create a project at supabase.com.
2. Open the SQL editor and run `supabase/schema.sql` top to bottom on a
   **fresh project**. The script is not an upgrade migration and is not safe
   to re-run against an existing schema. Back up existing data and prepare a
   reviewed migration before upgrading a live project.
   For an existing project that already ran this schema, apply the additive
   migrations in order: `0002_student_features.sql`,
   `0003_remove_student_id.sql`, then `0004_live_shuttle_and_cwa.sql`. Do not
   rerun the fresh schema.
3. Before login or registration, the database schema must be deployed. The
   app checks for the `profiles` table and explains this setup step if it is
   missing.
4. Project Settings → API: copy your **Project URL** and **publishable key**
   (or legacy **anon public key**).
5. To enable live vehicle pins, assign each approved operator from the SQL
   editor after they have an account and profile:
   ```sql
   insert into public.shuttle_operators (vehicle_id, user_id, label, route)
   values ('green-01', 'OPERATOR_PROFILE_UUID', 'Green shuttle 01', 'green');
   ```
   Operators share GPS only while they explicitly start tracking with the app
   open. Production background tracking requires native Android/iOS runners,
   platform location permissions, and separate background-location testing.
6. CWA is calculated as the credit-weighted average of entered percentage marks:
   `sum(score × credits) / sum(credits)`. Old GPA letter-grade records are
   preserved but excluded until their actual percentage marks are entered.
7. The application currently does not send push notifications; Firebase
   setup below is a starting point, not a complete notification integration.

For email confirmation and password reset on web, add the app origin to
Authentication → URL Configuration → Redirect URLs (for local development,
`http://localhost:8765/**`). Configure email confirmation and reset email
templates in Supabase Auth. The Google sign-in button is hidden unless enabled
by the app build and the Google provider is configured in Supabase.

## 3. Run locally
```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For web, use `flutter run -d chrome` after generating the web runner. Without
the defines above, the app intentionally starts on the Supabase setup screen.

You can use `SUPABASE_ANON_KEY` in place of `SUPABASE_PUBLISHABLE_KEY` for
projects that still use legacy anon keys. If no valid URL/key is supplied,
the app opens a setup screen instead of crashing. Never bundle a Supabase
service-role key in a client app.

## 4. Share the web test version
The public GitHub repository builds and deploys the test app to GitHub Pages
after changes reach `main` or the current preview branch. Set the repository
Actions variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` to the
Supabase project URL and its publishable client key. These values are intended
for client applications; never use a service-role key.

For this project, the test link is
`https://gabbylinkx.github.io/knust-hive/`. In Supabase Authentication →
URL Configuration, add
`https://gabbylinkx.github.io/knust-hive/**` to the allowed redirect URLs so
email confirmation and password reset links return to the test app. Keep the
existing redirect URLs. After the first successful deployment, share the link
with testers; they can register using their own email addresses.

The web test build is suitable for trying the student experience and
foreground browser GPS, but it is not a signed Android/iOS installer. Shuttle
GPS markers appear only after an administrator assigns real operator accounts.
Avoid using production student data when inviting external testers.

This repository snapshot may not include all Flutter platform runners.
Generate the runner(s) needed for your deployment with
`flutter create --platforms=android,web .` (or select other supported
platforms) before using `flutter run` or a platform build command. Choose and
configure the final Android application ID and signing credentials before
publishing.

## 5. Push notifications
Push notifications are not implemented yet. A Firebase project and FlutterFire
configuration alone will not enable them; app initialization, permission
prompts, device-token storage, server-side delivery, and platform-specific
configuration still need to be implemented and tested.

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

## 6. App icon, name, splash
- Update `pubspec.yaml` `name`/`description` as needed.
- Add `flutter_launcher_icons` and `flutter_native_splash` packages for
  branded icon/splash generation from a single source image.

## 7. Google Sign-In
Enable the Google provider in Supabase Auth settings, and follow
Supabase's [Flutter OAuth guide](https://supabase.com/docs/guides/auth/social-login/auth-google)
to register OAuth client IDs for Android/iOS (needed for the native flow).

## 8. Deployment
**Android (Play Store)**
```bash
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```
Upload `build/app/outputs/bundle/release/app-release.aab` via the
Play Console. You'll need a signing keystore — see Flutter's
[Android deployment guide](https://docs.flutter.dev/deployment/android).

**iOS (App Store)**
```bash
flutter build ipa --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```
Open the generated Xcode archive, or use `xcrun altool` / Transporter to
upload. Requires an active Apple Developer account. See Flutter's
[iOS deployment guide](https://docs.flutter.dev/deployment/ios).

## 9. Moderator access
The moderator queue is available under **More → Moderation**. A trusted
project operator must designate a moderator by setting `profiles.is_admin`
through the Supabase SQL editor or another trusted administrative process.
The client cannot update that column. Reports can be reviewed/resolved there;
content removal and marketplace dispute handling remain manual.

## 10. Feature boundaries
- Past questions store external HTTPS links; no document is uploaded or
  scanned by the app.
- The SOS button opens the device dialer for Ghana's 112 emergency number; it
  does not place a call automatically or share location.
- Timetable/CWA/community/marketplace/chat data require the schema and a
  reachable Supabase project. Deploying the SQL and providing credentials are
  required before those data-backed flows can be used.
