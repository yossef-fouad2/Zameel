# Project Context: Student Housing Marketplace

## Instructions for the AI Coding Agent

You are helping build a **Flutter mobile application that connects students with shared accommodation** and helps them understand whether a property’s household lifestyle is compatible with their preferences.

Treat this file as the source of truth for the project’s purpose and initial scope. Before implementing features, inspect the existing repository, understand its architecture and conventions, and propose a concise implementation plan. Do not rewrite working code or introduce unnecessary dependencies without a clear reason. Ask for clarification when a decision materially changes the product or data model.

## 1. Product Goal

Build a mobile marketplace where:

- **Landlords** can publish and manage accommodation listings.
- **Students** can discover accommodation, review details, and request a bed.
- Students can optionally share lifestyle preferences so the app can show potential compatibility with the people already living in a property.

The core value is not only finding a place to live; it is helping students make a more informed decision about the property and the shared-living environment before requesting accommodation.

## 2. Target Users and Roles

### Student
A student should be able to:
- Create and manage a profile.
- Browse accommodation listings.
- Explore listings on a map and filter the results.
- View property photos, location, rent, amenities, house rules, and bed availability.
- Optionally provide lifestyle preferences.
- Review a compatibility summary and its reasons when preference data is available.
- Submit a booking request and see its status.

### Landlord
A landlord should be able to:
- Create and manage a profile.
- Create, edit, publish, and manage their own accommodation listings.
- Add property photos, location, monthly rent, amenities, house rules, and total bed capacity.
- Review incoming booking requests.
- Accept or reject requests.
- Keep listing availability up to date.

Keep student and landlord permissions separate. A user must not be able to manage listings or booking requests they do not own or have permission to access.

## 3. Main Product Features

### A. Accommodation Listings and Discovery
Each listing should support, at minimum:
- Title and description.
- Address or map coordinates.
- Photos.
- Monthly rent, with the pricing unit made explicit (per bed, per room, or another defined unit).
- Amenities.
- House rules.
- Total bed capacity.
- Current availability/status.

Students should be able to browse listings, view them on a map, open a details page, and filter by relevant criteria such as rent, location/distance, and available beds.

Do not assume that every listing rents by the bed. Make the pricing and accommodation arrangement clear in the data model and UI, or ask for a product decision before locking in the schema.

### B. Bed Availability and Booking Requests
For each listing, distinguish between:
- Total capacity.
- Confirmed occupied beds.
- Pending booking requests.
- Available beds.
- Booking status.

A booking request should initially follow this workflow:
1. Student submits a request for an available bed or accommodation option.
2. Landlord reviews the request.
3. Landlord accepts or rejects it.
4. The student can see the resulting status.

Prevent overbooking. Availability must be checked and updated safely so two simultaneous requests cannot both claim the same last available bed. Do not treat a pending request as a confirmed reservation unless that rule is explicitly adopted.

### C. Student Lifestyle Preferences
During onboarding or profile editing, students may optionally specify preferences such as:
- Smoking preference.
- Preferred sleep schedule.
- Cleanliness expectations.
- Noise tolerance.
- Guest/social preferences.
- Preferred room-sharing arrangement.

Keep questions relevant, respectful, and optional where possible. Do not require unnecessary sensitive personal information. Clearly distinguish a student's own habits from the living conditions they prefer.

### D. Household Compatibility
The initial version should use a **transparent rule-based scoring algorithm**, not AI or machine learning.

The matching feature should:
- Compare a prospective student's preferences with the stated preferences or household conditions of current residents.
- Show understandable reasons for compatibility or possible conflicts.
- Handle missing or unanswered preferences without inventing data.
- Avoid presenting a score as a scientific or definitive judgment about a person.
- Never claim that a property is compatible when there is insufficient information.

A weighted score may be used, but weights are provisional and must be configurable or clearly documented. Do not hard-code example weights as final product requirements without confirming them.

## 4. Initial Technology Direction

- **Mobile app:** Flutter and Dart.
- **Backend platform:** Supabase.
- **Database:** Supabase PostgreSQL.
- **Authentication:** Supabase Auth, if authentication is required by the existing implementation.
- **Image storage:** Supabase Storage.
- **Location queries:** PostGIS may be used for nearby/map-based searches if appropriate.
- **Maps:** Use a suitable Flutter mapping package/provider after checking project dependencies and configuration.

Supabase is the intended backend platform. Do not introduce a separate Node.js, Express, or other custom backend unless explicitly requested. Use secure Supabase access patterns and Row Level Security (RLS) for data access control.

## 5. Suggested Domain Areas

Organize implementation around clear feature boundaries, adapting to the repository’s current architecture:
- `auth`
- `profile`
- `listings`
- `map` / `discovery`
- `matching`
- `bookings`
- `reviews` / `reporting` (later scope unless requested)

Potential data entities include:
- User/profile and role.
- Accommodation listing.
- Listing photos.
- Amenities and house rules.
- Lifestyle preferences.
- Household/resident relationships.
- Booking request.
- Reviews/reports (later scope).

These are conceptual entities, not a mandate to create every table immediately. Inspect existing schemas and migrations first, and avoid duplicating concepts already represented.

## 6. Security and Data Integrity

- Apply Supabase Row Level Security policies to all relevant tables.
- Students may manage only their own profile and booking requests, subject to defined permissions.
- Landlords may manage only their own listings and the requests associated with those listings.
- Validate all user inputs and enforce important constraints in the database as well as the UI.
- Do not expose service-role keys or other privileged secrets in the Flutter client.
- Store photos in Supabase Storage with suitable access policies.
- Avoid exposing private student information to unrelated users.
- Treat location and compatibility data carefully; reveal only what is needed for accommodation decisions.
- Prevent duplicate or conflicting reservations and handle failures gracefully.

## 7. MVP Priorities

Build in this order unless the repository or user gives a different priority:

1. Inspect the repository and report its current state, architecture, dependencies, and existing implementation.
2. Establish profiles and student/landlord roles.
3. Build accommodation listing creation and management, including photo upload and bed capacity.
4. Build student listing discovery, filters, map display, and listing details.
5. Implement booking requests, status transitions, and reliable availability tracking.
6. Add optional lifestyle preferences and transparent rule-based compatibility summaries.
7. Add polish, empty/loading/error states, validation, tests, and accessibility.

Do not build payments, chat, advanced landlord verification, machine-learning matching, or complex review systems in the MVP unless specifically requested. These may be future enhancements.

## 8. UI/UX Expectations

- Design for a clear, trustworthy, mobile-first student experience.
- Make rent, pricing unit, location, house rules, and availability easy to understand.
- Show listing photos and meaningful property details.
- Make map and list discovery work together.
- Use clear booking statuses and explain what happens after a request is submitted.
- Explain compatibility through specific matching factors rather than relying only on a percentage.
- Include loading, empty, validation, permission-denied, and error states.
- Follow the existing project design system and coding conventions where available.

## 9. How the Agent Should Work

Before making changes:
1. Inspect the project files and identify the current stack and architecture.
2. Summarize what already exists and what is missing.
3. Identify schema or product ambiguities that could cause expensive rework.
4. Present a step-by-step plan for the requested task.

When implementing:
- Make small, coherent changes.
- Reuse existing patterns and dependencies.
- Keep business logic separate from UI code.
- Add or update tests for important logic, especially matching and booking availability.
- Update database migrations and RLS policies together when changing data access.
- Never claim a feature works without checking the implementation or running relevant tests.
- Report files changed, decisions made, commands/tests run, and any remaining limitations.

## 10. Important Product Rules

- The app is a **student accommodation marketplace**, not merely a roommate personality quiz.
- Listings and map-based discovery are foundational.
- Lifestyle preferences are optional and support informed decisions.
- Compatibility is rule-based for the MVP; do not add AI/ML without an explicit change in scope.
- Landlords specify the property’s capacity; the system must track actual booking states separately.
- A pending booking request is not automatically a confirmed booking.
- Do not invent listing data, verification status, resident preferences, or compatibility results.
- When an important product rule is undecided, ask instead of silently choosing an implementation that will be difficult to reverse.
