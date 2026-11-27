# Flutter Sekitar — Agent Guide

Flutter client (iOS/Android) for the `cms_sekitarin` backend. Keep this file and
`README.md` in sync with every release. The backend release/update rules live in
`../cms_sekitarin/AGENTS.md`.

## Commands

```bash
flutter pub get
flutter analyze                  # must report no errors/warnings
flutter test
flutter run                      # production defaults
flutter build apk --debug --split-per-abi
```

- SDK: Flutter 3.50+/Dart 3.14 at `/home/theaska/flutter-sdk/flutter/bin/flutter`.
- APK builds need `JAVA_HOME=/home/theaska/jdk17`.
- Defaults: `API_BASE_URL=https://sekitarin.ckamal.com/api/v1`,
  `WS_URL=wss://sekitarinws.ckamal.com`; override with `--dart-define` for local
  development.

## Release checklist (mandatory)

Every user-visible change must ship as a documented app update:

1. Bump `version:` in `pubspec.yaml` (for example `0.12.0+16`).
2. Implement and test: `flutter analyze`, `flutter test`, plus backend contract
   tests when API behavior changes.
3. Build with `flutter build apk --debug --split-per-abi`.
4. Copy `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` to
   `../cms_sekitarin/web/data/app/sekitar.apk` (server, readable by `www-data`).
5. Update `../cms_sekitarin/web/data/app/latest.json` with `version`, `build`,
   `notes`, `url` (`/api/v1/app/download`), `published_at`.
6. Verify `GET /api/v1/app/latest` shows the new version and
   `"available": true`.
7. Add a row to the changelog below and update `README.md`.

The in-app **Setelan → Cek update** button compares `PackageInfo.version` with
the manifest and downloads/installs the APK.

## Changelog

| Date | Version | Highlights |
| --- | --- | --- |
| 2026-11-27 | 0.12.1+17 | Chat list uses relative “time ago”; chat room adds sticky date headers (day+month, or day+month+year across years) and message timestamps show minutes-ago under 60 minutes, then wall-clock `HH:mm`. |
| 2026-11-27 | 0.12.0+16 | Group live-location map (consent-gated) + share toggle; typing indicator in direct and group chats; tap group name for Group Info, info icon removed; editable group photo; business account photo/name/username editing with business-scoped usernames (not usable for login); commenter avatar, tappable profile, delete own comment; chat notifications moved to Chat tab badge and excluded from the bell; light/dark theme following system; offline "cannot connect to server" screen with retry; in-app update checker. |
| 2026-11-26 | 0.11.3+15 | Map viewport loading, distance labels, own-location tag, relative post times, post detail/actions, business activation countdown, settings account layout. |
| 2026-11-25 | 0.11.0+14 | Orders/rides, provider catalog, business location settings, notifications, comments and post detail. |
| 2026-11-24 | 0.10.0+13 | Chat + WebSocket, contacts/blocks, group create/manage, profile photo, usernames, feed. |
| 2026-11-23 | 0.9.0+12 | MVP auth, chat list, map, feed, profile, settings. |

## Conventions

- One tab per top-level feature under `lib/ui/`; shared widgets in
  `lib/ui/widgets/`; API access through `lib/core/api_client.dart`.
- Theme colors come from `Theme.of(context).colorScheme`; never hardcode white
  or black backgrounds so dark mode keeps working.
- Business account state is per active account (`activeAccountId`); business
  handles live in the `business` scope and must not be used to log in.
- Location sharing requires the `me/consents/location` consent; group map and
  live location only render members who granted it.
- Times from the API are UTC; display relative labels with helpers in
  `lib/ui/common.dart`.
