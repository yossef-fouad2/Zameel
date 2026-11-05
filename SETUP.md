# Zameel Setup

This is a Flutter app using Supabase Auth/PostgreSQL, Bloc, GoRouter, and English/Arabic localization. Complete the dashboard steps below before testing live authentication. Local tests use fakes and do not prove that your hosted project is configured.

## 1. Local Configuration

The root `.env` is a bundled Flutter asset, so it must exist when building. Keep it local and use **public client configuration only**, following `.env.example`:

```dotenv
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR-PUBLIC-ANON-KEY
GEOAPIFY_MAPS_API_KEY=YOUR-PUBLIC-GEOAPIFY-MAP-KEY
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
9. Run [supabase/007_university_discovery.sql](supabase/007_university_discovery.sql) for milestones 5 and 6. It adds the supplied university catalogue, protected walking-route cache, discovery RPC, and published-pin requirement.
10. Run [supabase/009_route_snapshot_transport.sql](supabase/009_route_snapshot_transport.sql). It enables lossless float serialization for the Data API roles and makes stale route snapshots non-retryable HTTP 409 conflicts. It preserves existing pins, cache rows and permissions; rerunning `007` does not perform this upgrade.
11. In development, run [supabase/008_university_discovery_verify.sql](supabase/008_university_discovery_verify.sql) after `009`. Its fixtures roll back and cover publication, cache privacy/invalidation, trusted writes, lossless transport settings, ordering and pagination. Do not run this fixture/DDL-locking verifier as a production diagnostic.
12. Run [supabase/010_room_type_pricing.sql](supabase/010_room_type_pricing.sql) as the original installation owner for optional double/triple room pricing. Apply it before releasing the updated client, which calls the versioned discovery RPC and submits room selections. It requires `001`, `007` and `009`, preserves existing generic data, and deliberately refuses reruns or incompatible objects rather than overwriting them.
13. In disposable development, run [supabase/011_room_type_pricing_verify.sql](supabase/011_room_type_pricing_verify.sql) after `010` and before testing the updated client. Its random fixtures roll back; it checks room edits, protected counters/RLS, immutable selected quotes, per-type allocation, legacy requests and v2 discovery. Do not run against production or external Auth/database hooks.
14. Keep `zameel_private` out of the API's exposed schemas and do not add broad permissive policies/grants to the application tables.

The setup creates profiles, listings, photos, amenities, house rules, optional lifestyle answers, bookings, resident links, RLS, a private photo bucket, and guarded booking RPCs. It inserts reference dictionaries only, not fake listings or users.

**Already installed `001`?** Apply only missing upgrades: `003`, `005`, `007`, `009`, then `010`; do not rerun `001`. Earlier upgrades have their documented checked-rerun behavior; `010` is intentionally a one-time migration and refuses reruns transactionally. For a fresh disposable database, use the full order **001, 002, 003, 004, 005, 006, 007, 009, 008, 010, 011**. `002` checks the old direct preference-write contract and belongs before `005`. `004` publishes an old address-only fixture and belongs before `007`. Use `006`, `008` and `011` for the corresponding upgraded contracts. Do not rerun `007` after `010`: its original preflight requires exactly the old listing columns and write allowlist. The original v1 discovery definition/fingerprint is retained, not rehashed to hide the schema extension.

The base milestone 7 booking flow uses the tables and guarded RPCs installed by `001`. Its optional room-type extension now requires `010`, not a rerun of the installer.

### Optional Room Types

- A listing may offer double rooms, triple rooms, both, or neither. Each enabled type has an integer room count and **one monthly price per bed shared by every bed of that type**. These are not whole-room prices or individually priced physical beds. A zero price is valid; a zero room count disables that type and requires its price to be `NULL`.
- Enabled options require `pricing_unit = 'per_bed'`. The database derives `total_bed_capacity = double_room_count * 2 + triple_room_count * 3` within the integer limit and `monthly_rent` as the cheapest enabled rate. Generic untyped capacity cannot be added on top. Both types are edited in the same listing CAS write; the server owns their occupied-bed counters and the aggregate occupancy.
- Existing listings start with both counts/counters at zero and both prices `NULL`; their original generic rent, capacity and occupancy remain untouched. Enabling options is blocked while any unassigned legacy request is pending or accepted. Removing a type is blocked while any request selecting it is pending or accepted; counts cannot shrink below that type's occupied capacity. These locked edits return `22023 / room_options_have_active_bookings` (client `room_options_locked`). Price edits otherwise remain allowed. There is no automatic reassignment, cancellation or repricing of historical requests.
- `submit_booking(p_listing_id, p_request_id, p_message DEFAULT NULL, p_room_type DEFAULT NULL)` requires exactly `double` or `triple` for enabled room options and `NULL` for a generic listing. The original three-argument overload is replaced, not kept alongside the new routine. Old two/three-argument clients still work for generic listings but fail closed with `room_type_required` on typed listings. Invalid/disabled or full selections return `room_type_unavailable` or `room_type_full`, even if the other type has free beds.
- Updated discovery uses `search_listings_by_university_v2` with the same parameters, defaults, flat fields, filtering, global distance/ID ordering and pagination as v1, plus the six room count/rent/occupancy columns. The original `search_listings_by_university` and its `007`/`009` fingerprint are unchanged for old clients, which continue to receive the aggregate summary.

### Property Maps And Walking Discovery

1. Create a Geoapify account and choose its no-card free tier for the graduation-project demo. Supply a public map key through `GEOAPIFY_MAPS_API_KEY` in the existing local client configuration, then restart. `flutter_map` uses Geoapify `positron` and `dark-matter` raster styles. Maps do not request device-location permission.
2. Create a separate routing key and store it as **`GEOAPIFY_ROUTING_API_KEY` in Supabase Edge Function secrets**, never in the bundled Flutter `.env`, a commit, or client code. The function also uses the Supabase-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` environment values.
3. After reviewing the target project and applying `007` and `009`, deploy the function with the Supabase CLI. Keep JWT verification enabled; the handler also verifies the user, persisted landlord role and listing ownership. The privileged key is used only for the narrow cache-write RPC, not direct table access.

```powershell
supabase functions deploy refresh-listing-routes --remote=YOUR_PROJECT_REF --use-api
```

- Map tiles and walking calculations consume provider credits. Monitor the free-tier dashboard, apply supported key restrictions, and do not enable paid fallback or assume unlimited usage. The map key is public client configuration, not an authorization boundary.
- The 16 supplied Egyptian university records are reference locations, **not verified entrances**. Names, cities and coordinates are preserved. Review actual pedestrian access before a demo; an endpoint snapped more than 100 metres from its pin is not advertised as a usable route.
- Landlords confirm a pin locally, then Save persists the listing and calculates missing walking connections. A routing failure leaves the saved property intact and exposes Retry. Publishing discloses the exact pin publicly. New publications require a pin; legacy address-only publications remain stored but are excluded from walking discovery until repaired.
- Existing listings with coordinates need their owner to open the editor and select **Refresh walking connections** to populate the new cache. Administrator changes to university pins similarly require refreshing affected listings. Old coordinate snapshots are hidden immediately rather than shown as current.
- Refresh fills missing/stale connections, reusing current outcomes to conserve quota. There is no scheduled expiry or automatic refresh for changes to the provider's pedestrian network. Deliberate recalculation of a current outcome requires administrator cache maintenance or a reviewed routing-version change. Expanding beyond the 16-location demo catalogue also requires reviewing the function and writer batch limits.
- Students choose a university in Explore. The query includes only published properties with a current usable walking route of at most 10,000 metres, sorted by unrounded distance then listing ID before pagination. All published bed-availability states are shown honestly. Selection is stored as `university_selection_v1:<userId>` on this device; it is not a verified enrolment or a cross-device profile preference.
- Photo uploads, amenity/house-rule editors, saved properties, broader filters and map-wide browsing remain outside the agreed lean listing/discovery release. Booking requests are now implemented separately by M7. Details do not fabricate unavailable fields or features.
- After repairing legacy published rows, an administrator may validate the new constraint: `alter table public.listings validate constraint listings_published_pin;`. Do not delete or unpublish existing data as a shortcut.

The authenticated endpoint accepts only `{ "listing_id": "UUID" }`. It derives coordinates from the database, considers all active universities within a conservative 11 km candidate envelope, and requests shortest metric walking routes. The 11 km prefilter is **not** the displayed distance or final cutoff. Stale backend completions are rejected under database locks. Parallel Edge isolates may duplicate a provider request, but cannot overwrite an already-current result.

The function has a 45-second total deadline, below Flutter's 60-second invocation timeout. It bounds SDK calls and response bodies as well as provider requests; a timed-out caller cannot evict another caller's live refresh or dispatch new work after its deadline. Function edits require redeployment; Flutter hot reload and local `config.toml` health-timeout settings do not update this budget. `--use-api` bundles on Supabase without requiring local Docker.

Migration `009` is required independently of the Edge deployment. With `extra_float_digits=0`, JSON can round a stored `double precision` pin, so even a freshly read snapshot fails the writer's exact comparison. `009` sets the three Data API roles to lossless output rather than rounding or changing stored coordinates. The writer uses `PT409` for genuine stale snapshots: older PostgREST versions retry `40001` indefinitely, even when an application deliberately raises it. The migration reloads API configuration and retains all ownership, RLS and locking checks. Verify a fresh API read round-trips exactly and a stale snapshot returns HTTP 409 promptly before testing a successful owner refresh.

The cache writer calls the existing `public.write_listing_university_routes` RPC directly over authenticated PostgREST HTTP. It uses the platform's service-role credential only for that endpoint, never a direct table write. This avoids constructing a second Auth-enabled SDK client and waiting on Auth initialization/session lookups for a static-credential write. Caller authentication, RLS-protected reads, snapshot validation and SQL locking remain unchanged. The writer's response body is size-limited and cancelled on timeout; HTTP errors and malformed counts never report completion.

For a persistent `504 / refresh_timeout`, inspect the returned `stage` and `request_id`. Match that ID to the `listing_routes_refresh` JSON record in Edge Function Logs; it contains status, a safe error code, total elapsed milliseconds and per-stage timings, never credentials, account/listing IDs, coordinates or raw provider responses. `authentication`, `profile`, `listing` and `route_cache` identify Supabase reads; `geoapify` identifies the routing request/body; `cache_write` identifies the guarded RPC; `shared_refresh` identifies a caller waiting on another refresh. These distinguish the stalled dependency without assuming every timeout comes from Geoapify. A cache-write response can be lost after commit: retry the same saved property to reuse current cached results, not a new listing or a cleared cache. Repeated attempts can still consume provider credits when no current result was saved.

### Booking Requests

- Students request one bed from a published per-bed property, select an enabled room type when offered, optionally include a message of at most 2,000 Unicode code points, and track requests in the Requests tab. Whole-room and whole-property allocation remains deliberately unsupported.
- Landlords open Booking requests from their listing dashboard. The inbox starts with pending requests; acceptance and rejection require confirmation. Students may cancel pending or accepted requests, with an explicit warning that cancelling an accepted request releases its bed.
- `submit_booking` records the latest server price for the selected type at submission, never a client-supplied or previously displayed price, plus currency, pricing unit and the aggregate capacity/occupancy snapshot. `bookings.room_type` and the quote are retained after future edits, option removal or unpublication. Pending requests occupy no beds; acceptance claims exactly one bed of the selected type and accepted cancellation releases that same type and aggregate bed exactly once. Generic legacy requests continue to use aggregate allocation. Clients never write status, occupancy or resident rows directly.
- A student's request history uses a left listing join, so an archived/inaccessible property does not erase the request or prevent permitted cancellation. Only its original quote and request information remain visible. Landlord views do not fetch private student profile names, phone numbers, email addresses or lifestyle answers.
- Lost write responses are uncertain, not failures that can be retried with a new ID. Submission keeps the same request ID, frozen message and frozen room selection; changing any payload field is not a retry. Decision retries repeat the same action. Reload reconciles with the server. Leaving an uncertain submission warns the student to check Requests; this is not an offline submission queue.
- All booking requests resolve and validate the expected SDK account before dispatch and bind its bearer token only to that request. Session persistence/refresh stays with the SDK. Account-keyed state and post-response checks prevent an old request or refresh from appearing under a replacement account.

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
- Create and edit a landlord property, cancel and confirm map selection, save a private draft, acknowledge exact-pin publication, and archive/return to draft. Check that another landlord cannot write it and a student cannot refresh its routes or forge cached distances.
- Test walking routes around the actual university pins and property entrances used in the demo. Include one property near more than one university, a route near the 10 km boundary, an unreachable route, and a changed pin while calculation is in flight. Provider coverage and gates must be checked on the ground; these are not navigation/safety guarantees.
- Select and switch universities as a student. Verify nearest-first results across pages, per-account remembered selection, public details and unavailable private/archived deep links. No routing-provider request should run during student searches.
- Test missing/invalid map credentials, missing function deployment, quota errors, offline tiles and failed routing. Existing coordinates and saved listings must survive. Compare two-device listing edits and real concurrent cache writes on hosted PostgreSQL.
- Submit a per-bed request with and without a message. Confirm it is pending, consumes no capacity, appears only to its student and the listing owner, and retains its submitted quote after a rent edit. Per-room/whole-property requests and direct status/occupancy writes must fail.
- Create/edit double-only, triple-only, mixed and generic properties, including a zero rate. Confirm the derived capacity and cheapest-rate summary, selected server quote, legacy-active conversion lock, active type-removal lock and count-reduction boundary. A full double type must not consume a free triple bed, or vice versa; old null-selection clients must fail closed on typed properties.
- Accept and reject from the landlord inbox, then refresh the student's Requests tab. Cancel pending and accepted requests and verify only accepted cancellation releases a bed and closes its resident link. Archive a listing and confirm the student's request/quote remains accessible without revealing the hidden listing or private profiles.
- Use separate native PostgreSQL connections for last-bed acceptance per type, accept/cancel, duplicate-submit, option enable/disable and listing capacity/archive races. Check statuses, type/aggregate occupancy and resident links together; a stale decision must not resurrect a rejected/cancelled request. Follow the room-specific race guidance in `011`; the full legacy `002` verifier must not be rerun after the upgrades noted above.
- Simulate losing a submit/decision response after commit. Reload or retry the exact attempt and verify there is no duplicate request or extra capacity change. Test both Back paths while editing, busy and uncertain; leaving must never submit implicitly.
- Switch accounts while a booking read/write or expired-token refresh is pending. No old message or result may appear in the replacement account, and no delayed request may use its credentials. Verify the same account can still refresh an expired token and submit normally.
- Check booking cards, status transitions, confirmation dialogs, keyboard-visible messages and narrow/large-text English/Arabic layouts on devices in both themes, with reduced motion on and off. Profile-mode device measurements, not widget tests, establish frame-rate behavior.

## 5. Current Feature Boundaries

- Account sign-in, confirmation, reset, profile-backed roles, and logout are implemented.
- Profile editing and private avatars are implemented. The migration and app tests have been run locally; hosted Storage HTTP, device picking, and frame-rate measurements still need the live/device checks above.
- Milestone 4.5 cloud preference sync is implemented with atomic answer/onboarding saves, private student-only access, conflict protection and reviewed local-draft import. Hosted RPC/RLS and cross-device acceptance still need the checks above after deploying `005`.
- Milestones 5 and 6 implement the agreed lean landlord listing and university-based discovery flows. Page bindings and Cubits are separate from replaceable views, shared housing components and the map renderer. Hosted map/route/device acceptance remains required.
- Milestone 7 implements student request submission/history/cancellation and landlord review/acceptance/rejection over the existing RPCs, with immutable quotes, safe retries and account isolation. Hosted booking/RLS/concurrency and physical-device acceptance remain required. Compatibility summaries are next (M9); M8 preferences are already covered by M4.5.
- The database supports explicit price units and currency. After `010`, optional double/triple room types each have one shared per-bed monthly rate and independent capacity. Booking RPCs still allocate one `per_bed` place, not an entire room/property or a particular numbered bed.
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

Localization tests read the actual English/Arabic assets. App tests use mocked SDK transport and repositories, without live credentials. Map tests inject image providers rather than contacting tile servers. Edge checks can be run with Deno 2 (initial package resolution needs network, test transport does not):

```powershell
deno task --cwd supabase/functions/refresh-listing-routes check
deno task --cwd supabase/functions/refresh-listing-routes test
```

Discovery verifier `008` previously passed 183 assertions in isolated embedded PostgreSQL with Auth/Storage stubs. The Edge handler passed 19 fake-transport groups with runtime network/environment/filesystem access denied. These checks do not prove hosted PostgREST/JWT configuration, real provider coverage, or two-connection race behavior.

Milestone 4.5 local verification on 2026-10-18: clean analysis and **149 passing Flutter tests**. The `001 -> 006` SQL sequence also passed in isolated PGlite 0.5.10 / PostgreSQL 18.6: 115 foundation, 53 avatar, 216 preference assertions and 21 supplemental migration checks; avatar verification was repeated after `005`. Only Supabase roles/Auth/Storage metadata were mocked, with no extension shims. This is not hosted PostgREST/JWT validation or a native concurrent-race test; keep those live checks separate.

Milestone 7 local verification on 2026-10-31: `flutter pub get` and localization generation succeeded, analysis is clean, the milestone formatting check passes, and **399 Flutter tests pass**, including **101 booking model/service/state/UI tests**. Review fixes were re-reviewed and cover the token-refresh account-switch race, stale landlord decisions, onboarding integration and normal/reduced-motion behavior. No SQL/Edge checks were rerun, hosted requests made, or physical-device performance measured during this continuation.

Room-pricing SQL verification on 2026-11-04: `011` passes **186 rollback-only assertions**, and an isolated harness passes **41 additional migration/refusal/preservation checks** on PGlite 0.5.13 / PostgreSQL 18.6. The full SQL install/upgrade/verifier sequence passes, including `008` again after `010`. Existing generic rows, pre-upgrade pending/accepted requests and the original v1 search definition/fingerprint are preserved. Only Supabase Auth/Storage metadata and roles were stubbed; no project credentials or hosted data were used. Native two-connection races, PostgREST schema reload/default-argument dispatch and hosted JWT/RLS acceptance remain separate checks.

## 7. Platform Features

No native configuration was changed. Internet access is required for live Supabase, tiles and server-side routing. Confirm network access in the actual release-mode device build; manual map selection needs no location/GPS permission. The avatar feature uses the existing `image_picker` gallery picker; no camera feature was added. Check the package's iOS photo-library usage-description requirements before an iOS device build, and verify cancelled/denied selection on supported devices. Store releases and optional external deep links remain separate setup work. Do not replace the entire Podfile or manifest to add a single permission.

Keep the personal progress checklist in `MILESTONES.md`; it is intentionally local and ignored by Git.
