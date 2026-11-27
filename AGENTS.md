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
| 2026-11-27 | 0.12.23+39 | Fix login/register payload: `_devicePayload` is async and must be awaited, otherwise JSON encoding fails with “Instance of Future<Map>” and login never reaches the server. |
| 2026-11-27 | 0.12.22+38 | Login diagnostics: detailed network/TLS/timeout errors and a “Tes koneksi ke server” button on the login screen showing API URL/status. |
| 2026-11-27 | 0.12.21+37 | Force-reset FCM token from Settings to replace stale/invalid tokens (`deleteToken` + new token registration). |
| 2026-11-27 | 0.12.20+36 | Push diagnostics: device login now reports the real app version; FCM token registration retries after login/resume; Settings shows “Notifikasi push” status and a manual re-register action. |
| 2026-11-27 | 0.12.19+35 | Android relaunch as **Sekitarin** with package `com.kamal.sekitarin`; Firebase client config + FCM push (token registration, background notifications, notification-tap to chat), Android 13 permission; WebSocket auto-reconnect and live chat-list/badge refresh. Installing this build replaces the old `net.emetrotel` package, so the old app must be uninstalled first. |
| 2026-11-27 | 0.12.18+34 | One combined Chat list for all accounts: incoming business chats render “my business avatar/name < sender”, outgoing business chats show the target business; replies use the thread’s own account. Profile edit button hidden for business accounts. |
| 2026-11-27 | 0.12.17+33 | Group avatars visible to every member and refreshed live; map follows dark mode via a free tile filter and marker icons scale with zoom; direct chats are scoped per account (all account types) with an active-account chip; chat supports photo and file attachments (PDF/Word/Excel/TXT/ZIP). |
| 2026-11-27 | 0.12.16+32 | Fix random logouts: refresh is single-flight (parallel 401s share one rotation) and only a rejected refresh token clears the session — network/timeout/429/5xx keep it. Backend refresh rotation now updates only if the old token still matches, returning 401 on races. |
| 2026-11-27 | 0.12.15+31 | Map driver markers use bare vehicle icons (no circle); the header profile button shows the active account photo and, for non-personal accounts, a bottom-right badge with that account type's icon; nearby distance is now returned for own/contact posts too and shown whenever known. |
| 2026-11-27 | 0.12.14+30 | Tapping a profile that belongs to any of your accounts (not just the active one) switches to it and opens the existing Profile page; other accounts open the read-only posts profile. |
| 2026-11-27 | 0.12.13+29 | Map self marker is now a location icon; chat headers show call + video-call buttons (group: video only, no-op for now); feed/post/comment avatars and names open a read-only profile with the same post grid, or the existing Profile page when it is your active account. |
| 2026-11-27 | 0.12.12+28 | Maps reverted to light OSM tiles even in dark mode (CARTO dark tiles need a key); shared `ThemeMapTileLayer` kept for a future keyed provider. |
| 2026-11-27 | 0.12.11+27 | Group avatars are now visible to every group member (backend media access allows group-avatar media for conversation members); all maps use CARTO dark tiles in dark mode and OSM light tiles otherwise. |
| 2026-11-27 | 0.12.10+26 | Update progress is inline on the Settings “Cek update” row (no progress dialog) with adaptive MB/percent and cancel; downloaded APKs are cached per version so “Pasang” retries the installer without re-downloading. Bottom navigation is now Chat / Peta / Post / Log Telepon (empty placeholder); profile opens from the header icon, and Settings from the profile AppBar. |
| 2026-11-27 | 0.12.9+25 | Nearby posts show their distance in the feed card (“Sekitar 850 m / 1,2 km dari kamu”, with a near-me icon) and on the post detail header; detail preserves feed distance metadata after reloading the post. |
| 2026-11-27 | 0.12.8+24 | Personal accounts now publish their position when “Bagikan lokasi” is on (business fixed pins stay put), so nearby feed works for personal users; feed falls back to public posts from the last 7 days labeled “Terbaru” when nobody is nearby; the chat list shows “sedang mengetik…” per conversation (direct and group) over WebSocket with ref-counted subscriptions. |
| 2026-11-27 | 0.12.7+23 | Feed always requests the viewer position when loading (consent no longer blocks “posts around me”) and uses a 2 km radius; backend feed default radius is now 2000 m. |
| 2026-11-27 | 0.12.6+22 | Group map opens on the user's own GPS position (with a recenter button and 1-hour share that auto-grants consent); Android header shows only the Sekitarin mark without the adjacent wordmark. |
| 2026-11-27 | 0.12.5+21 | Chat header shows the conversation photo before the name for both direct and group chats (no avatar in AppBar actions); group avatars get a group badge overlay in the header, chat list, and Group Info. |
| 2026-11-27 | 0.12.4+20 | Feed posts and direct-chat rows now show the poster/peer profile photo (backend peer payload includes handle + avatar); new Contacts list screen replaces the empty search page, with add-contact FAB; direct chat offers “add to contact” when the peer is not saved; sent bubbles use a darker container in dark mode with readable metadata text. |
| 2026-11-27 | 0.12.3+19 | In-app update shows download progress (percentage, MB downloaded/total, status, cancel/close) before opening the installer; header/login logo now uses the blue app icon (`assets/brand/app_icon.png`) instead of the custom teal mark. |
| 2026-11-27 | 0.12.2+18 | Per-group location sharing switch in Group Info (profile-level toggle removed); any member can change the group photo; group chat always shows the group avatar at the top-right with the standard back button restored; contacts button only on the Chat tab; chat badge clears server-side when the Chat tab is opened; unread chats highlighted with bold text + badge; Sekitarin logo on the home header and login screen. |
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
- **Chat header:** show the conversation photo **before the name** for both
  direct and group chats, keep the default back button on the left, and never
  put the avatar in the AppBar actions. Group avatars always carry a small
  group badge (`lib/ui/widgets/group_avatar.dart`) in the header, chat list, and
  Group Info.
- **Location sharing is per group.** Configure it from Group Info; do not add a
  profile-level share toggle. Enabling it also grants the location consent
  needed by the API.
- **Group photo** can be changed by any member; only the group name stays
  owner-only. Backend mirrors this rule.
- **Branding:** the Sekitarin logo (`lib/ui/widgets/sekitarin_logo.dart`) sits at
  the top-left of the home header and on the login screen. It uses the blue app
  icon at `assets/brand/app_icon.png`; replace that asset (and the launcher
  icons) together when a final brand icon is ready.
- Chat list timestamps use time-ago; never show absolute dates there.
- **Chat badge:** never show the bottom Chat badge while the Chat tab is
  selected; only badge when the user is on another tab.
- **Chat cache:** messages are cached per conversation in `ChatCache`; opening a
  chat uses the cache and only fetches messages after the last cached id. Clear
  the cache on logout, clear-chat, and delete/leave.
- **Typing label:** direct chats show only “sedang mengetik…”; groups include the
  typing member names. Keep the keyboard from hiding the last message by
  scrolling to the bottom when input focus/metrics change.
- **Message feedback:** play `MessageSound` for new incoming/sent messages and
  animate newly added bubbles once (fade + slide). Suppress the chat-list sound
  when that conversation is already open (`ChatPresence`).
- **Message status:** outgoing bubbles show clock (pending), one check (sent),
  double check (delivered), double check blue (read). Sending inserts an
  optimistic pending bubble immediately; replace it with the server message.
  `messages.delivered` and `read.updated` WS events update counts.
- **Chat list styling:** full-bleed rows with no card radius or side padding;
  use dividers between rows.
- **Clear vs delete:** “Bersihkan pesan” is per-user (`cleared_before_message_id`)
  and never deletes for other members. Direct “Hapus percakapan” and group
  “Keluar grup” use the existing conversation DELETE/leave endpoint.
- **Profile edit:** show the Edit button only for the personal account. Business
  accounts change name/photo/location from the business settings screen, not
  from the Profile edit sheet.
- **Direct chats are account-scoped.** Each pair of accounts has its own
  conversation, but the Chat tab shows **all threads in one list** (groups stay
  user-level). Do not add an active-account filter or a “Chat sebagai …” chip.
  Direct rows are rendered from `my_account` + `peer`:
  - message received by my business account → my business avatar/name `<` sender
    avatar/name;
  - chat I started with a business account → that business avatar/name;
  - personal-to-personal → the other person.
  Reply identity uses the conversation's `my_account_id`, never the globally
  active account.
- **Navigation:** the bottom bar has exactly four tabs — Chat, Peta, Post, Log
  Telepon. Profil is opened from the top-right header icon; Setelan is opened
  from the Profil AppBar. Do not add Profil/Setelan back to the bottom bar.
- **Updater:** keep update progress inline on the Settings row, never in a
  dialog; cache the APK per version so installing can be retried without a new
  download.
- **Push:** Android package is `com.kamal.sekitarin` with display name
  **Sekitarin**. Firebase config comes from `android/app/google-services.json`
  (Git-ignored) or `--dart-define`; never hardcode credentials. Push must stay
  optional so the app runs without Firebase config; FCM token
  registration/logout is handled in `AuthStore`.
- **Maps:** use the shared `ThemeMapTileLayer` (light OSM). CARTO dark tiles
  require an API key now; do not re-enable keyless dark tiles.
