# pokepedia_mobile

# Flutter Directory Structure

A suggested Flutter project layout that mirrors the **feature-first, layered
architecture** of the current Lynx app. The goal is to keep the same separation
of concerns so the mental model carries over 1:1 when porting.

## The layering idea

Every feature is split into three layers, exactly like the Lynx version:

| Layer            | Responsibility                                                                                   | Lynx equivalent                    |
| ---------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| **presentation** | UI only — screens and feature-scoped widgets. No business logic.                                 | View (`*Page.tsx`) + `components/` |
| **usecase**      | Application/business logic. Validates input, orchestrates repositories, exposes state to the UI. | `usecase/` (react-query hooks)     |
| **repository**   | Data access. Talks to the API client, maps responses into models.                                | `repository/` + `type.ts`          |

Data flows in one direction:

```
presentation  ──calls──▶  usecase  ──calls──▶  repository  ──▶  network/API
     ▲                       │                      │
     └────── state ──────────┘◀──── models ─────────┘
```

Shared, cross-cutting code lives outside `features/` so any feature can use it
without creating feature-to-feature dependencies.

## Directory tree

```
project_root/
├── android/
├── ios/
├── assets/
│   ├── images/
│   └── fonts/
├── pubspec.yaml
└── lib/
    ├── main.dart                       # app entry point
    │
    ├── app/                            # app shell: root widget, DI init, routing
    │   ├── app.dart                    # MaterialApp / root widget
    │   ├── bootstrap.dart              # startup wiring (DI, providers)
    │   └── router/
    │       ├── app_router.dart         # route table
    │       └── routes.dart             # route name constants
    │
    ├── core/                           # cross-cutting shared layer
    │   ├── constants/                  # api config, endpoints, static values
    │   ├── network/                    # HTTP client + interceptors
    │   │   ├── api_client.dart         # Dio instance
    │   │   ├── auth_interceptor.dart   # 401 handling + token refresh
    │   │   └── api_response.dart       # generic response wrapper
    │   ├── platform/                   # native bridge / platform channels
    │   ├── providers/                  # global app-scoped providers (auth, toast, ...)
    │   ├── theme/                      # colors, typography, app theme
    │   └── utils/                      # helpers (validation, storage, files, time, ...)
    │
    ├── shared/                         # design-system / reusable widgets
    │   └── widgets/
    │       ├── ...                     # app-level widgets (text, input, button, modal, ...)
    │       └── common/                 # atomic building blocks (card, badge, shimmer, ...)
    │
    └── features/                       # one folder per feature
        └── <feature>/
            ├── presentation/
            │   ├── <feature>_page.dart # screen (the view)
            │   └── widgets/            # feature-scoped widgets
            ├── usecase/
            │   ├── <feature>_notifier.dart      # business logic / state
            │   └── <feature>_validation.dart    # input validation (when needed)
            └── repository/
                ├── <feature>_repository.dart    # data access
                └── models/                       # DTOs / domain models
```

## Conventions

- **Feature isolation** — a feature never imports from another feature. Anything
  shared moves up into `core/` or `shared/`.
- **presentation depends on usecase, usecase depends on repository** — never the
  reverse. The repository knows nothing about the UI.
- **One notifier per use case** — mirror the Lynx habit of one hook per action
  (e.g. separate notifiers for "load", "submit", "update") rather than one giant
  controller.
- **Models live with their repository** — response/request types stay next to the
  data layer that produces them (`repository/models/`).
- **Routing replaces per-page bundles** — Lynx compiles one bundle per page; in
  Flutter each feature is registered as a named route in `app/router/`.

## Notes on state management

The `usecase/` layer maps most naturally to **Riverpod** — a usecase notifier
consumes a repository provider the same way a Lynx `useX` hook consumes a
`useXRepo` hook, and Riverpod's `AsyncNotifier`/`FutureProvider` cover the
caching/refetch role that react-query played.

If **Bloc/Cubit** is preferred instead, rename `usecase/` to `cubit/` (or
`bloc/`); the rest of the structure and the dependency direction stay the same.
