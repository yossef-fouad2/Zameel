# Property Map and University Discovery

**Goal**
Deliver a lean, real landlord-to-student flow: a landlord confirms the property's exact map pin; the app derives walking distances to nearby universities; a student selects a university and browses qualifying published properties from nearest to farthest.

**Agreed Scope**
- Rank by estimated **walking-route distance**, not straight-line distance or travel time. Include routes of **10,000 metres or less**, inclusive.
- Use the 16 Egyptian university locations supplied below. They are reference pins, not independently verified pedestrian entrances or a complete catalogue of every campus.
- Published property pins are public, including through the existing database API. Show landlords a clear notice before publishing. Drafts remain owner-only.
- Put university selection at the top of Explore. Remember the choice per account on the same device using SharedPreferences; allow changing it anytime. No new signup step, profile column, or cross-device preference sync.
- Implement basic listing create/edit/draft/publish/archive, map selection, nearby-university results, student cards, and read-only details.
- Defer listing-photo uploads, booking screens, advanced filters, saved properties, student-wide map browsing, route polylines/navigation, address autocomplete, GPS shortcuts, multiple entrances per university, and administrative catalogue UI. Do not present these as working features.
- Graduation-project default: `flutter_map` with Geoapify map tiles and walking routing on its no-card free tier. No paid subscription, additional custom backend, background job system, or PostGIS dependency is needed for this small catalogue.

**Repository Baseline**
- `supabase/001_marketplace_setup.sql:151-181` already provides paired coordinates and bounded values. Its published-location rule currently also permits address-only listings. Ownership/RLS, explicit price units, generated availability, and `set_listing_status` must remain authoritative.
- `lib/src/ui/student/discovery_page.dart` is an empty discovery shell. `lib/src/routing/app_router.dart:175-192` currently sends landlords to `AccountPage(landlordLanding: true)`. There are no listing/university models, repositories, map packages, or real discovery queries yet.
- Reuse the repository/service/feature-Cubit patterns, `FutureEither`/`runTask`, central dependency injection in `state_wrapper.dart`, and central routing. Follow `DESIGN.md`, English/Arabic localization, and the actual `package:zameel` import namespace. Preserve auth, profile, lifestyle, and booking contracts.

**University Catalogue**
Preserve the supplied IDs, names, cities, and coordinate precision. Validate the import; do not silently move pins, invent additional locations, or describe these as verified gates. Show the supplied English names in either locale until reviewed Arabic names are available.

| ID | Name | City | Latitude | Longitude |
|---|---|---|---|---|
| 1 | Cairo University | Giza | 30.0276 | 31.21014 |
| 2 | Ain Shams University | Abbassia, Cairo | 30.077022 | 31.285017 |
| 3 | Al-Azhar University | Nasr City, Cairo | 30.0583 | 31.3126 |
| 4 | Alexandria University | Alexandria | 31.20194 | 29.90528 |
| 5 | Assiut University | Assiut | 27.187778 | 31.170278 |
| 6 | Tanta University | Tanta | 30.7922 | 30.9992 |
| 7 | Benha University | Benha | 30.471111 | 31.181667 |
| 8 | Suez Canal University | Ismailia | 30.622778 | 32.275 |
| 9 | Fayoum University | Fayoum | 29.3211 | 30.8356 |
| 10 | Beni-Suef University | Beni Suef | 29.081389 | 31.100556 |
| 11 | Aswan University | Aswan | 23.9989 | 32.8599 |
| 12 | October 6 University | 6th of October City | 29.976167 | 30.948528 |
| 13 | German University in Cairo (GUC) | New Cairo | 29.988 | 31.442 |
| 14 | The American University in Cairo (AUC) | New Cairo | 30.019944 | 31.500344 |
| 15 | British University in Egypt (BUE) | El Shorouk City | 30.117778 | 31.606389 |
| 16 | Arab Open University (AOU) - Egypt | El-Shorouk City, Cairo Governorate | 30.1297 | 31.615 |

**Data Contracts**
| Object | Contract |
|---|---|
| `public.universities` | Integer ID, supplied name/city, non-null bounded latitude/longitude, active flag. Public read of active catalogue entries; administrator-only maintenance, no client writes. One reference location per entry. |
| `public.listing_university_routes` | Derived cache, keyed by listing/university. Store both endpoint coordinate snapshots, routing-version identifier, calculation timestamp, outcome (`ready`, `unroutable`, `needs_pin_review`), and nullable finite non-negative `distance_m`. A ready result requires a distance; other outcomes have no distance. Store matched endpoint coordinates for checking snap offsets. |
| Cache visibility | Readable only for an accessible listing and current endpoint snapshots/routing version. Published rows follow the existing public visibility; draft results are owner-only. Clients cannot insert/update/delete distances. Do not expose stale rows via direct table reads or RPCs. |
| Trusted cache write | A narrow server-only SECURITY DEFINER RPC with an empty search path and qualified objects accepts provider results, verifies endpoint snapshots against current database coordinates, and writes atomically. Revoke default PUBLIC/client execution. Grant only the required backend access; do not add broad privileges to existing tables. |
| Discovery RPC | `search_listings_by_university(p_university_id, p_after_distance_m, p_after_listing_id, p_limit)` returns explicit listing fields plus distance. Use SECURITY INVOKER/RLS, an explicit published-only predicate, active university, current cache inputs, ready outcome, and `distance_m <= 10000`. Order by unrounded `(distance_m, listing_id)` before keyset pagination; default 20, cap 50. Validate IDs, limits, and the paired cursor. |

A property can appear for several universities. The route table is a computed cache, not a landlord-declared affiliation or a permanent single-nearest-university assignment. Include published properties regardless of bed availability in this first slice; show the actual availability and pricing unit rather than adding an unrequested availability filter.

**Implementation Order**
1. **Add the database upgrade.** Create `supabase/007_university_discovery.sql` and rollback-only `008_university_discovery_verify.sql`, following the existing transactional migration conventions: checked no-op on unchanged reruns, safe refusal of conflicting objects, preserved existing data and permissions. Add the catalogue, cache, policies, narrow cache-write RPC, search RPC, and an index supporting university/distance ordering. Use an additive `NOT VALID` CHECK requiring coordinate pairs on published listings: new publication/updates must have a pin, while existing address-only published rows are not rewritten or removed. They remain excluded from walking discovery until repaired; validate the CHECK after those rows are corrected. Never rerun or replace the fresh-only `001` installer.

2. **Implement trusted route calculation.** Add `supabase/functions/refresh-listing-routes/index.ts` using the existing Supabase platform and Deno's fetch, not a separate server. Accept a listing ID, validate the caller's Supabase identity, and check the persisted landlord role and listing ownership before any provider request. Read coordinates from the database rather than accepting caller-supplied endpoints or distances. Use the caller's RLS context for those reads; keep the routing credential and narrowly used privileged cache writer server-side.

3. **Bound and cache routing work.** Check all active university pins, not merely the three geographically closest. A great-circle prefilter of 11 km limits intercity requests; it is only a conservative candidate envelope, not a student-facing distance. Send missing eligible pairs to Geoapify Route Matrix with property as source, universities as targets, `mode: walk`, `type: short`, and `units: metric`. Matrix coordinates are `[longitude, latitude]`, unlike the supplied table order. Reject malformed/non-finite results and flag matched endpoints displaced more than 100 m as `needs_pin_review`; the wider candidate envelope accounts for this bounded snapping. Apply the real 10 km walking cutoff only to returned route distances. Cache valid outcomes, including unreachable or over-10-km results, to avoid repeat calls. Reuse only matching endpoint snapshots and routing settings; discard obsolete responses. Keep refreshes explicit and bounded, honor quota/rate errors, prevent duplicate UI submissions, and avoid automatic retry loops. No routing requests occur when students change university. No scheduled cache refresh is required for the demo; catalogue-coordinate changes require an explicit route refresh for affected listings.

4. **Add typed app data access.** Under `lib/src/data/models/`, introduce university, listing/draft, and distance-result types with finite coordinate validation and explicit status/price-unit parsing. Add injectable `UniversityRepository` and `ListingRepository` implementations under `data/repositories/` with services under `services/`; register them in `state_wrapper.dart`. Cover catalogue reads and account-keyed last selection, owned listing create/read/update/status operations, route refresh, published discovery, and detail reads. Do not add listing deletion. Send only permitted listing fields. Use the existing `updated_at` optimistic-concurrency pattern for edits; preserve timestamp precision. Do not blindly retry an ambiguous create response and risk duplicate listings.

5. **Build the landlord flow.** Replace the landlord landing shell with an owned-listings page, retaining a clear account/profile entry. Add a feature-specific editor Cubit and form for title, description, address, monthly rent, explicit currency/pricing unit, total bed capacity, and map pin. Draft saving still needs the database's required commercial fields; a pin is required for publication. Retain server-owned owner/status/occupancy fields and publish/archive through `set_listing_status`. A full-screen map picker opens at the existing pin, or lets the landlord choose a university as a starting viewpoint. Tap to place/move the pin and explicitly Confirm; merely opening/centring the map never selects the university's location as the property. Cancel preserves the previous draft. Map interaction stays local; Save persists the listing, then refreshes route results when needed. Show nearby universities sorted by their computed walking distance. Protect dirty Back navigation, busy controls, and conflicting saves.

6. **Build student discovery and details.** Add an account-keyed discovery Cubit. Load the catalogue and remembered university, or show a choose-university prompt. A deleted/inactive saved ID returns to that prompt. Selection immediately starts a fresh paginated query; discard earlier university/account responses and reset pagination. Show a visible `Within 10 km walking` scope and cards with title, rent/currency/unit, genuine availability, and an estimated walking-distance label. Details load fresh authorized data, show the exact property pin and selected university reference pin, and explain that routes depend on mapped pedestrian access. Archived/inaccessible/deleted listings show unavailable state. Keep existing Requests/Match/Saved boundaries honest; no fake photos, match scores, or booking buttons.

7. **Integrate maps and UI.** Add compatible stable `flutter_map` and `latlong2` dependencies, without another state/routing library or production HTTP layer. Keep map rendering reusable between picker and details, with injected tile configuration/providers for tests. Use Geoapify light/dark raster styles and visible linked Geoapify, OpenStreetMap, and applicable OpenMapTiles attribution. Add a public map-key placeholder to `.env.example`; the route key belongs only in Edge Function secrets. A client map key is not a secret: apply supported restrictions and monitor quota. Missing map configuration disables the map with actionable feedback, not auth/profile startup. Register all new named routes in `app_router.dart`/`app_routes.dart`, preserving landlord/student guards, `appTransitionPage`, and reduced motion. Add both locales and regenerate localization keys. Preserve existing native files and real `.env` contents.

8. **Document and validate deployment.** Update existing `SETUP.md` with the new migration/verifier order, Edge Function deployment/secrets, public tile configuration, attribution, explicit refresh procedure, and demo acceptance checks. Do not connect to or mutate a hosted project without separate authorization. Record only checks actually run. Keep listing photos, bookings, and broader discovery milestones marked unfinished rather than claiming the entire marketplace is complete.

**Failure Rules**
- Persisting a listing and computing routes are separate outcomes. Route failure must not lose saved property fields or produce a misleading total-save failure. Show `Property saved; walking distances unavailable` with explicit Retry.
- Publication can succeed with a valid public pin even if routing is unavailable. Warn that the listing is not included for a university until a matching, usable cached route exists. Missing/stale/unreachable routes never become zero or straight-line walking distances.
- Existing valid cached routes remain usable through provider outages while their input coordinates match. A changed property/university pin makes old routes unreadable immediately through the snapshot predicates, even before refresh succeeds.
- Save conflicts and uncertain network responses preserve drafts and require reload/reconciliation. Changing accounts or leaving a screen must not apply an earlier response to a different account or listing.
- Map load failures preserve existing coordinates and show retry/error state. Do not silently confirm a new location on an unloaded map. Discovery still works from saved route data when tiles are unavailable.
- Empty discovery copy means no published properties with a usable route within 10 km, not proof that no housing exists nearby. Walking values are estimates to the supplied reference pin, not verified gate access, safety guarantees, or live navigation.

**Validation**
1. Unit/transport tests: all 16 supplied records and IDs; coordinate bounds/NaN/infinity; latitude-longitude conversion; required listing fields and allowed write payloads; zero distance versus missing route; 10 km boundary; candidate-envelope/snap checks; route-direction/settings; wrong/missing matrix cells; negative/non-finite values; no-route and quota errors; cache reuse/invalidation; saved-listing/failed-routing distinction; stale refresh and save responses.
2. SQL verification: owner-only listing writes, rejected forged distances/university edits, public published versus private draft reads, stale cache hidden from direct reads and RPCs, only server cache writes, stale completion rejected, migration reruns/data preservation, legacy address-only behavior, invalid search arguments, stable ties, and globally ordered multiple pages. Include a fixture where walking order differs from straight-line order. Assert that drafts/archived listings never appear, including for their owner.
3. Widget/state tests: create/edit/pin restoration, explicit confirmation and cancellation, dirty Back, publication disclosure, route retry, switching universities during an in-flight query, account-isolated saved choice, pagination reset, missing catalogue/configuration, unavailable detail, and truthful empty states. Exercise English/Arabic, RTL, light/dark, narrow/wide layouts, large text, keyboard, and reduced motion. Map tests must not contact live tile servers.
4. Run `flutter pub get`, localization generation, `flutter analyze`, and `flutter test`; run Deno tests for the Edge Function with fake transport and SQL checks in an isolated development database. Preserve the documented old migration/verification order (`002` is before `005`); run the new verifier after `007`.
5. Before the live demo, configure the free provider account and authorized Supabase deployment, then test real walking coverage and endpoint snapping around every supplied university pin used in the demo. Check several landlord-controlled properties, including one qualifying for more than one university. Review campus entrances with the team rather than silently replacing coordinates. Test quota/network failure and one cross-owner denial through the real API. Verify Internet access on the demo device and document any native setup prerequisite without editing native project files in this task.

**External References**
- Geoapify [Route Matrix](https://apidocs.geoapify.com/docs/route-matrix/) and [Routing](https://apidocs.geoapify.com/docs/routing/): walking mode, distance-optimized routes, metric distances, endpoint matching, and unavailable routes.
- Geoapify [Map Tiles](https://apidocs.geoapify.com/docs/maps/map-tiles/), [Pricing](https://www.geoapify.com/pricing/), and [Terms](https://www.geoapify.com/terms-and-conditions/): attribution and quota requirements. Documentation checked on 2026-10-19 advertises 3,000 free credits/day without a credit card; maps and routing share usage. Do not promise unlimited free usage or enable a paid fallback.
- [flutter_map installation](https://docs.fleaflet.dev/getting-started/installation): compatible map dependencies and platform network prerequisites.

**Handoff Status**
Ready for implementation with the agreed lean scope. Provider-account setup, hosted deployment authorization, and real route/pin checks are execution/acceptance prerequisites, not evidence that the feature already works. Planning inspected source and provider documentation only; no application code, SQL, secrets, or native configuration was changed, and no tests or live routing/Supabase calls were run.
