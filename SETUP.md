# Zameel Setup

This is a Flutter app using Supabase Auth/PostgreSQL, Bloc, GoRouter, and English/Arabic localization. Complete the dashboard steps below before testing live authentication. Local tests use fakes and do not prove that your hosted project is configured.

## 1. Local Configuration

The root `.env` is a bundled Flutter asset, so it must exist when building. Keep it local and use **public client configuration only**, following `.env.example`:

```dotenv
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR-PUBLIC-ANON-KEY
```

Alternatively use `SUPABASE_PUBLISHABLE_KEY=sb_publishable_...` instead of `SUPABASE_ANON_KEY`. When both are present, the publishable-key setting takes precedence. Get the URL and public key from your project's API settings.

- The public publishable/legacy `anon` key is intended for client apps. RLS, not hiding this key, protects the database.
- Never put a `service_role` JWT, `sb_secret_...` key, database password, SMTP password, or other privileged credential in any Flutter asset.
- `AppConfig` rejects placeholder URLs and privileged keys. A setup screen appears instead of attempting auth with bad configuration. Restart after updating `.env`.
- SDK session persistence is used; the app does not manually cache tokens.

```powershell
flutter pub get
```

## 2. SQL Editor Setup

Use [supabase/001_marketplace_setup.sql](supabase/001_marketplace_setup.sql), **not the old `dbSchema` draft**.

1. Open a fresh Supabase project and its SQL Editor.
2. Review the setup file's opening notes, then execute the entire file in one query as the database administrator.
3. Confirm that the transaction succeeds. The installer intentionally refuses an existing/incompatible application schema, existing custom Auth triggers, or conflicting Storage policies. It does not drop or overwrite them. A previously used project needs a reviewed migration, not another run of this installer.
4. In a disposable development project, run [supabase/002_marketplace_verify.sql](supabase/002_marketplace_verify.sql). Its test fixtures roll back. Read its prerequisites before running it.
5. Keep `zameel_private` out of the API's exposed schemas and do not add broad permissive policies/grants to the application tables.

The setup creates profiles, listings, photos, amenities, house rules, optional lifestyle answers, bookings, resident links, RLS, a private photo bucket, and guarded booking RPCs. It inserts reference dictionaries only, not fake listings or users.

### Existing Auth Accounts

New email signups send `name` and a chosen `role` (`student` or `landlord`). The Auth insert trigger creates the protected profile once. Later metadata changes do not change that role.

Users created **before** this setup require a reviewed backfill. As administrator, find missing profiles:

```sql
select u.id, u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
```

Then explicitly choose the role for each account:

```sql
-- Replace the placeholder with the reviewed Auth user ID.
select zameel_private.backfill_profile('REVIEWED-USER-UUID', 'student');
-- Use 'landlord' only for an account intended to own listings.
```

Backfill is idempotent for existing profiles and never overwrites a saved role. Do not bulk-trust editable Auth metadata. A missing/invalid profile produces an app error screen with Retry and Sign Out, not a guessed student role. Landlord signup is self-selection, not identity or property-ownership verification.

## 3. Email Confirmation And Recovery

The app uses **codes entered in the app**, so the core email flow does not depend on changing Android/iOS URL schemes.

1. Enable email/password sign-in in Supabase Auth settings. Keep **Confirm email** enabled for normal use.
2. Set the minimum password length to at least 8 to match signup/reset validation. Sign-in accepts existing nonempty passwords without imposing the new-signup minimum.
3. Configure email delivery. Supabase's default email service has recipient/rate restrictions; configure your own SMTP provider before testing with arbitrary addresses or releasing.
4. Under Auth email templates, put `{{ .Token }}` in both **Confirm signup** and **Reset password** bodies. Keep any project-specific branding you want, but make the code clearly visible. The stock link-only templates are not sufficient for this app's code-entry flow.
5. Review OTP expiry and Auth rate limits. The app applies a 60-second resend cooldown; server-side limits remain authoritative.

Example confirmation template body:

```html
<h2>Confirm your Zameel account</h2>
<p>Enter this code in the app:</p>
<p><strong>{{ .Token }}</strong></p>
<p>If you did not request this account, ignore this email.</p>
```

Example reset template body:

```html
<h2>Reset your Zameel password</h2>
<p>Enter this code in the app, then choose your new password:</p>
<p><strong>{{ .Token }}</strong></p>
<p>If you did not request a reset, ignore this email.</p>
```

Signup with no session stays on Check Email. The code is verified with `OtpType.signup`. A real session returned when confirmation is disabled is also handled, but disabling confirmation is not required or recommended to make the UI work.

Password reset requests a recovery email, verifies `OtpType.recovery`, and keeps navigation on the new-password screen until `updateUser(password: ...)` succeeds. Cancel signs out. Invalid/expired codes, failures, and retries are visible. Forgot-password messaging does not confirm whether an address exists.

Google, university SSO, and social sign-in are **not enabled or advertised as functioning**. Those providers need credentials and a reviewed initial-role flow before their buttons return.

## 4. Live Acceptance Checklist

Use accounts and data you control. These checks must be performed on your project; mocked tests cannot replace them.

- Create a student with confirmation enabled. Verify no private screen opens until the email code succeeds and a valid profile loads.
- Confirm the profile has the selected role and `full_name` from signup `name`.
- Sign out, sign back in, restart the app, and verify session restoration.
- Request a password reset; test a wrong/expired code, then a valid code and new password. Verify the old password no longer works.
- Create/confirm a landlord and verify it lands in the landlord workspace. Test that student routes redirect away for that account and landlord routes redirect away for a student.
- Change the user's own Auth metadata `role` during a controlled test. It must not change the persisted profile role or permissions. Do not change the protected database role just to test metadata behavior.
- Verify direct API attempts cannot update `profiles.role`, another user's profile, listing ownership/status/occupancy, or booking states outside the RPCs.
- Skip or complete the optional quiz, sign out/in on the same device, and verify returning students reach Discovery. Another account must not inherit those answers.
- Check English and Arabic, light/dark, a narrow screen, enlarged text, keyboard-visible forms, and system Back behavior on a device.

## 5. Current Feature Boundaries

- Account sign-in, confirmation, reset, profile-backed roles, and logout are implemented.
- Student onboarding choices/lifestyle answers are still **account-scoped local storage**. SQL prepares a private preferences table, but no cloud synchronization is claimed.
- Discovery and the landlord workspace are honest landing shells. Listing management, real discovery/map queries, booking screens, and compatibility summaries are later milestones.
- The database supports explicit price units and currency. Booking RPCs currently support `per_bed` only; room/property booking allocation is deliberately rejected until its model is implemented.
- Pending requests do not occupy beds. Acceptance/cancellation use locked database operations. Client code must not write occupied-bed counters or booking status directly.
- Photo objects use the private `listing-photos` bucket. Follow the paths, upload/delete order, and signed-URL guidance in the SQL header; do not use public URLs.
- Files do not deploy themselves. This work does not connect to, inspect secrets from, or execute SQL against your hosted project.

## 6. Design And Validation

See [DESIGN.md](DESIGN.md) for the Kinship-inspired Zameel theme and [REUSABLES.md](REUSABLES.md) for the reusable-component inventory. Plus Jakarta Sans and IBM Plex Sans Arabic are bundled with their OFL licenses; font loading works offline and does not contact Google Fonts.

```powershell
flutter pub get
flutter pub run easy_localization:generate -S assets/translations -O lib/src/core/i18n -o locale_keys.g.dart
flutter analyze
flutter test
flutter run
```

Localization tests read the actual English/Arabic assets. Auth tests use mocked SDK transport and repositories, without live credentials.

## 7. Platform Features

No native configuration was changed for the code-based auth flow. Internet access is required for live Supabase requests. Camera/photo permissions, maps, store releases, and optional deep links should be configured only when their features are implemented, using the package/platform setup guides. Do not replace the entire Podfile or manifest to add a single permission.

Keep the personal progress checklist in `MILESTONES.md`; it is intentionally local and ignored by Git.
