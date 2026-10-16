# Zameel feature architecture

The repository uses feature folders inside the generated `lib/src` layout. The
older `presentation/` example is intentionally not used; keeping all feature
code under `ui/` avoids duplicate architectural roots.

```text
lib/src/
├── data/
│   ├── models/          # immutable domain/data models and typed enums
│   └── repositories/    # interfaces plus persistence/backend implementations
├── services/            # shared platform and storage services
├── routing/             # the single GoRouter configuration
├── shared/
│   ├── widgets/         # reusable visual primitives
│   ├── helpers/         # overlays and formatting helpers
│   └── wrappers/        # app-wide localization, state, and lifecycle wrappers
├── theme/               # Material 3 tokens and semantic status colors
└── ui/
    ├── auth/            # role selection and authentication flow
    └── student/
        ├── onboarding_bridge_page.dart
        ├── discovery_page.dart
        └── lifestyle_quiz/
            ├── lifestyle_quiz_page.dart
            ├── lifestyle_quiz_bloc.dart
            └── (typed quiz data lives in data/)
```

## Responsibilities

- **Pages/widgets** render state and dispatch user intent; they do not call
  Supabase or SharedPreferences directly.
- **Blocs** own screen flow state and delegate persistence to repositories.
- **Repositories** expose `FutureEither` operations and hide storage/backend
  details from the UI.
- **Models** are immutable, typed, and serializable. Nullable quiz fields are
  intentional so skipped or incomplete answers remain honest missing data.
- **Routing** is centralized in `lib/src/routing/app_router.dart` and route
  names are declared in `app_routes.dart`.
- **Reusable UI** uses the theme tokens and shared widgets instead of adding
  one-off buttons, cards, or color values inside feature pages.
