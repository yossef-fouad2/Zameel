# Quiz-Based Compatibility Estimates And Ranking

Status: Draft. The household source and Gemini scoring engine are confirmed; rubric, coverage, disclosure and assessment-lifecycle policies remain unresolved. Do not start implementation or treat proposed choices as approved.

## Confirmed Direction

- After the student completes the quiz, show listings with personalized compatibility estimates and use the resulting score for Best Match sorting.
- Lifestyle only: rent and walking distance do not contribute to the lifestyle score. Preserve the existing university discovery boundary.
- A ranking score is not a probability of successful co-living, a judgment of someone's character, or a booking eligibility decision.
- Reuse the existing optional quiz as the required matching input; do not introduce an extra priority-note or conversational-advisor flow. Students who skip the quiz must still be able to browse and book.
- Household source: reuse existing quiz answers voluntarily shared by students with active accepted bookings for the listing. Sharing requires explicit, revocable consent and limited household findings rather than public identities or raw profiles. Describe the data as stated preferences, not verified physical occupancy or observed household behavior.
- Gemini generates the estimated numeric score and reasons. Our backend supplies only permitted inputs, enforces information requirements and explicit constraints, validates and versions results, and sorts them. The rule-based scorer is an evaluation baseline, not an undisclosed replacement for Gemini estimates.
- Keep Flutter and the existing Supabase backend. Use Supabase Edge Functions for secure Gemini calls and PostgreSQL for persistence, guarded data access and global sorting; no separate Node.js/Express backend is needed.

## Target Student Flow

1. Complete the existing optional lifestyle quiz, then open university-based discovery.
2. The backend compares the requesting student's saved answers against the agreed, permitted household data for each eligible listing.
3. Each listing card shows an estimated lifestyle fit when enough information exists; otherwise it shows Not enough information without a made-up score.
4. Best Match ordering uses those assessed scores. Details show matching factors, possible conflicts, and unknowns. Nearest-first remains available, including when matching is unavailable.
5. Booking continues through the existing workflow, independently of the compatibility estimate.

## Responsibility Boundaries

- The backend enforces authorization, information coverage, explicit constraints, validated result contracts, and stable global ordering before pagination.
- Gemini returns structured rubric-constrained scores, factor findings and reasons. Use a documented rule-based baseline for evaluation and do not claim validated prediction of co-living outcomes. If Gemini fails or returns invalid/stale output, expose an unavailable estimate and keep discovery usable rather than silently substituting a different engine's score.
- AI must not invent household conditions, derive importance solely from selected quiz values, change preferences, or make booking decisions.
- Define whether Best Match becomes the post-quiz default or remains an explicit sort choice before changing existing nearest-first behavior.

## Evidence And Constraints

- `lib/src/data/models/lifestyle_preferences.dart:102,159-175`: the displayed quiz covers sleep, study atmosphere, dishes, guests, and room sharing. It does not collect factor importance.
- `lib/src/data/models/lifestyle_snapshot.dart:119-133,159-179`: sleep is stored as a habit; the other displayed answers are preferences. Normalized rows retain optional intensity, but its meaning must be established before reusing it as a ranking weight.
- `supabase/001_marketplace_setup.sql:632-649`: preferences are self-only; resident links are visible only to their student or the owning landlord. Existing access does not permit prospective students to read residents' quizzes.
- `supabase/001_marketplace_setup.sql:540-544,552-559`: accepted bookings create resident links; cancellation ends them. These links do not establish verified physical move-in.
- `lib/src/data/models/listing.dart:59-76`: current listing reads provide rent, location, capacity and status, not a verified room arrangement or household lifestyle.
- `supabase/007_university_discovery.sql:361-398`: discovery globally orders eligible published listings within 10 km walking by distance and ID before keyset pagination. Sorting only the already-loaded Flutter page would be incorrect.

## Decisions Required Before Implementation

1. Consent and disclosure details: the shared-quiz source is approved, but default-off sharing scope, minimum contribution requirements, small-household disclosures, audience and retention still need precise policies. Recommendation: listing-scoped opt-in and a narrowly authorized student-only assessment API; do not call accepted bookings verified current occupancy or promise anonymity merely because answers are aggregated.
2. Score scale and importance: specify a stable score scale and provisional configurable factor importance within the documented Gemini rubric. Do not reinterpret existing intensity or invent personalized importance from quiz selections. Track model, prompt and rubric versions with each estimate.
3. Rubric: define comparable factors, their meaning, provisional configurable importance, treatment of differing participant answers, and any explicitly declared non-negotiables. Preference similarity is not proof of behavior; sleeping late does not establish noise, and matching room-sharing preferences does not establish the property's room layout.
4. Coverage and privacy: define minimum information and contribution requirements, handling of unanswered or unshared factors, disclosure limits for small households, and where unassessed listings appear. Missing data must not become either agreement or incompatibility, or produce a falsely favorable ranking.
5. Assessment lifecycle and sorting: choose bounded generation/refresh behavior for the full eligible candidate set, default sort after quiz completion, exact ranked cursors and invalidation. Best Match must not secretly mean sorting only the nearest page or whichever model calls finished first.

## Ordered Implementation Work After Decisions

1. Align product documents before code changes. Revise `PROJECT_CONTEXT_STUDENT_HOUSING.md` section D, MVP item 6 and rule 10; replace the rule-based-only prohibition with the approved AI-assisted ranking scope while retaining transparency and missing-data safeguards. Update `MILESTONES.md` M9. Align the proposal's aim, objective 5, proposed solution, AI expected outcome and technology description, plus corresponding report scope and evaluation sections. Obtain any required supervisor agreement; do not assume academic approval.
2. Add only the approved household-data and assessment persistence. Author new migrations, grants and RLS/guarded APIs together; leave existing private quiz access intact. Sharing must be voluntary and revocable, without restricting discovery or bookings. Define cancellation, answer-edit and consent-revocation invalidation, retention, and disclosure behavior before storing derived data.
3. Implement the approved versioned assessment contract and deterministic baseline in the server/data layer. Return assessed/unassessed status, ranking score when justified, coverage, grounded factor reasons and conflicts. Preserve mixed answers rather than averaging away an important conflict. Establish stable tie-breaking and test the baseline independently of Gemini.
4. Add an authenticated Supabase Edge Function for Gemini-generated compatibility estimates. Follow the existing handler/entrypoint separation in `supabase/functions/refresh-listing-routes/`; verify the requester and retain request-local account binding. Keep Gemini credentials server-side, minimize transmitted data, allowlist factors, and validate score bounds, factor references and consistency with explicit constraints. Treat listing text and any user-supplied content as data, not privileged instructions. Add input limits, timeouts, rate limits, configurable model selection, versioned prompts and safe failure behavior; no private participant identities or unnecessary raw answers go to Gemini. Reuse only assessments whose input and engine versions are still current rather than regenerating inconsistent scores on every page request. Check consent and input freshness again before committing late model responses.
5. Add an authenticated ranked discovery query without changing the existing public nearest-first contract. Apply the same geographic eligibility rules, calculate ordering over the eligible set before the page limit, and define an exact cursor including the ranking context. Specify snapshot or stale-context rejection/restart behavior for preference, weight, consent and membership changes before implementation. Distance may be a secondary tie-breaker, not a lifestyle factor.
6. Extend existing discovery and preference state/presentation boundaries. Add listing-card estimates, the approved sort, detailed factor explanations and unavailable states; keep data access and scoring out of widgets. Reset account-bound results and pagination on relevant changes. Do not gate a booking on quiz completion, AI availability, or a compatibility score.
7. Validate and roll out. Cover matching, differing preferences, partial answers, zero contributors, insufficient coverage, small-household disclosure, invalid model output, service failures, consent withdrawal, cancellation, account switching and stable multi-page ordering. Evaluate estimates and explanation grounding against explicit expected inputs and a non-AI baseline; check repeated model requests for inconsistent judgments. Run Flutter analysis/tests and relevant SQL/Edge tests; hosted authorization, concurrency, provider privacy/configuration and device acceptance remain separate checks. Deploy new backend contracts before enabling ranked UI; preserve nearest-first when ranking is unavailable.

## Out Of Scope

- Rent/commute in the lifestyle score, an extra priority questionnaire or natural-language priority flow, general-purpose chat, a separate custom backend, automatic booking decisions, sensitive-trait inference, custom model training, verified move-in workflows and unapproved landlord questionnaire expansion.
- Source and product-document edits during this planning pass. This draft does not authorize implementation.
