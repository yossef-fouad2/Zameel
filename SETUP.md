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
5. Run [supabase/003_profile_avatars.sql](supabase/003_profile_avatars.sql) to enable milestone 4. This app version reads `profiles.avatar_path`, so apply this migration before using the updated app.
6. In development, run [supabase/004_profile_avatars_verify.sql](supabase/004_profile_avatars_verify.sql). It checks profile permissions, private avatars, and compatibility with the original schema using rolled-back fixtures.
7. Run [supabase/005_lifestyle_sync.sql](supabase/005_lifestyle_sync.sql) for milestone 4.5. The updated student flow calls its preference RPCs, so apply it before using this app version.
8. In development, run [supabase/006_lifestyle_sync_verify.sql](supabase/006_lifestyle_sync_verify.sql). It checks private atomic saves, revision conflicts, skip/completion metadata and validation with rolled-back fixtures.
9. Keep `zameel_private` out of the API's exposed schemas and do not add broad permissive policies/grants to the application tables.

The setup creates profiles, listings, photos, amenities, house rules, optional lifestyle answers, bookings, resident links, RLS, a private photo bucket, and guarded booking RPCs. It inserts reference dictionaries only, not fake listings or users.

**Already installed `001`?** Apply `003` if it is not installed, then `005`. Use `004` and `006` for the corresponding development checks; do not rerun `001`. Neither migration wipes existing profiles or answers. Unchanged migration reruns are checked no-ops; incompatible objects are refused rather than replaced. `002` checks the original direct preference-write contract and belongs **before** `005`; after `005`, use `006` for the new RPC-only contract.

### Profile Editing And Avatars

- The account page edits name, optional phone, and language. Email and role stay read-only. A saved language applies across the app and is restored on future sign-in.
- Avatars use the private `profile-avatars` bucket, separately from listing photos. Only the owner can read/sign/upload/delete their objects. Current profile photos cannot be deleted directly.
- The client resizes selected images to a maximum 512-pixel side, re-encodes PNG to strip source metadata, and limits uploads to 2 MiB. It uses the system gallery picker, not broad storage permissions.
- Photo changes are previews until Save. Uploads use new versioned paths with `upsert:false`; only `avatar_path` is stored in the profile. Legacy external `avatar_url` values are retained in the database but are not used as private photos by this editor.
- Signed URLs last 10 minutes and are fetched on profile load/photo change, not during typing or every frame. A signed URL or already downloaded image can remain usable until expiry/cache removal after sign-out or replacement.
- Saves compare the original `updated_at` timestamp. Concurrent edits return a conflict instead of silently overwriting another device. Full timestamp precision must be preserved.
- Retired photos are cleaned up after a confirmed save. A network response can be lost after the server commits, so an uncertain upload is not blindly deleted. Unreferenced objects may require later cleanup through the Storage API. Never delete `storage.objects` rows directly in production.

### Lifestyle Preferences Across Devices

- Answers remain in `public.lifestyle_preferences`; `zameel_private.lifestyle_sync_state` holds the questionnaire revision and completion/skip metadata. The private schema must not be exposed through the API.
- `get_lifestyle_preferences` and `save_lifestyle_preferences` require the authenticated account ID and a database-backed student role. The save RPC checks the original revision and commits answers plus metadata together; client direct insert/update/delete grants on answers are removed. Do not replace this with a table upsert or weaken RLS.
- A completed quiz contains the five displayed answers. Skipping may contain partial answers or none. Missing answers are absent rows, not guessed values. Habit/preference distinctions and existing unedited answer kinds/intensities are retained. Server timestamps record completion/skip; clearing answers leaves a revision tombstone so a stale device cannot resurrect deleted data.
- Existing server answers are preserved by migration without inventing completion. They take precedence over older device-only answers. Existing version-1 local drafts are staged only when the account has no cloud revision, with a review notice; they are **not** uploaded during sign-in or a read.
- Review a staged draft in the quiz, then explicitly choose Save or Skip and save progress to upload it. Leaving without saving keeps the local copy. The onboarding bridge will not upload an older local draft on the user's behalf. A confirmed import removes only that account's old local key; failures keep it unchanged.
- This is explicit online save, not offline autosave or a background upload queue. Load failure blocks writes. Failed saves retain selections; conflicts and uncertain network responses require checking the latest cloud snapshot before another save. A transient optional-data refresh does not tear down an already authenticated editor.
- The repository coalesces concurrent reads but fetches fresh data on later openings. Selections do not write to Supabase or local storage. A successful quiz save updates session onboarding directly, without re-fetching the profile.

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
- Edit name/phone/language, save, and verify both the database and current session update. Repeat after restarting; confirm role and email cannot be edited through profile requests.
- Choose, replace, and remove a photo; verify private signed display and that another account cannot read or modify the object. Test cancelled picking, failed uploads, and retry.
- Edit the same profile in two sessions: the later stale save must report a conflict and preserve the draft. Verify Back/Discard warns before losing unsaved changes.
- Save or skip the quiz, then sign in on a second device and verify both answers and onboarding choice. Check partial answers and clearing an answer without inventing a replacement.
- Edit the quiz on two devices. After one saves, the other's stale save must fail without overwriting; reload/discard is explicit. Simulate losing a save response and verify the app checks the cloud before retrying.
- Verify another student, a landlord and an anonymous client cannot read or write the student's preference snapshot or private state. Direct answer writes must fail after `005`.
- Upgrade with an old device-only draft. Sign-in must not upload it. Review it in the quiz and confirm only an explicit save/skip imports it; cancelled navigation, failed requests and account switching must not lose or cross-copy answers.
- Check quiz toolbar and system Back while dirty and while saving, rapid selections, reduced motion, Arabic/English large text, and actual scrolling/transitions on target devices in profile mode.

## 5. Current Feature Boundaries

- Account sign-in, confirmation, reset, profile-backed roles, and logout are implemented.
- Profile editing and private avatars are implemented. The migration and app tests have been run locally; hosted Storage HTTP, device picking, and frame-rate measurements still need the live/device checks above.
- Milestone 4.5 cloud preference sync is implemented with atomic answer/onboarding saves, private student-only access, conflict protection and reviewed local-draft import. Hosted RPC/RLS and cross-device acceptance still need the checks above after deploying `005`.
- Discovery and the landlord workspace are honest landing shells. Listing management, real discovery/map queries, booking screens, and compatibility summaries are later milestones.
- The database supports explicit price units and currency. Booking RPCs currently support `per_bed` only; room/property booking allocation is deliberately rejected until its model is implemented.
- Pending requests do not occupy beds. Acceptance/cancellation use locked database operations. Client code must not write occupied-bed counters or booking status directly.
- Listing photo objects use `listing-photos`; profile photos use `profile-avatars`. Both are private. Follow each SQL file's path and access rules; do not use public URLs.
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

Milestone 4.5 local verification on 2026-10-18: clean analysis and **149 passing Flutter tests**. The `001 -> 006` SQL sequence also passed in isolated PGlite 0.5.10 / PostgreSQL 18.6: 115 foundation, 53 avatar, 216 preference assertions and 21 supplemental migration checks; avatar verification was repeated after `005`. Only Supabase roles/Auth/Storage metadata were mocked, with no extension shims. This is not hosted PostgREST/JWT validation or a native concurrent-race test; keep those live checks separate.

## 7. Platform Features

No native configuration was changed. Internet access is required for live Supabase requests. The avatar feature uses the existing `image_picker` gallery picker; no camera feature was added. Check the package's iOS photo-library usage-description requirements before an iOS device build, and verify cancelled/denied selection on supported devices. Maps, store releases, and optional deep links remain separate setup work. Do not replace the entire Podfile or manifest to add a single permission.

Keep the personal progress checklist in `MILESTONES.md`; it is intentionally local and ignored by Git.
