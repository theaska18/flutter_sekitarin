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
| 2026-11-27 | 0.12.51+67 | Keep recvonly video in Jingle session-accept (without requiring local video SSRC), mark it `senders=initiator`, and retain per-m-line audio/video/data ICE credentials. Added regression test. |
| 2026-11-27 | 0.12.50+66 | Send SourceVideoTypeMessage and ReceiverVideoConstraints on JVB data-channel open and when peers join; preserve call-debug uploads (fix broken retention that deleted every diagnostic row). |
| 2026-11-27 | 0.12.49+65 | Delay opening the WebRTC call screen until the app is resumed (CallKit accept leaves the Flutter activity in the background, which previously dropped the route on the callee). CallKit's incoming notification is dismissed before joining. |
| 2026-11-27 | 0.12.48+64 | Use our local ICE credentials/fingerprint for the data content in the Jingle session-accept (it previously carried JVB's credentials from the offer, causing 401 connectivity checks and DTLS timeouts). |
| 2026-11-27 | 0.12.47+63 | Fix duplicate incoming-call notifications: dedupe by call id across WS/FCM, suppress WS ringing while backgrounded, and dismiss the CallKit incoming UI immediately on accept. |
| 2026-11-27 | 0.12.46+62 | Use the applied local description (not the raw createAnswer SDP) for the Jingle session-accept and escape transport attributes; fixes ICE 401/DTLS timeout when the answer credentials were not yet final. |
| 2026-11-27 | 0.12.45+61 | Temporary call diagnostics: the client uploads the Jingle offer, remote SDP, local SDP and session-accept to `/me/call-debug` so the DTLS/media failure can be inspected server-side. |
| 2026-11-27 | 0.12.44+60 | Apply Jitsi source-map renegotiation (VideoSourcesMap/AudioSourcesMap from the data channel) so JVB starts sending RTP; added media renegotiation diagnostics. |
| 2026-11-27 | 0.12.43+59 | Announce audio/video sources in the XMPP presence (`SourceInfo`) so Jicofo includes media sections in the session-initiate. |
| 2026-11-27 | 0.12.42+58 | Show live WebRTC media diagnostics (ICE/DTLS state, inbound/outbound KB, remote track counts) on the call screen to debug missing audio/video. |
| 2026-11-27 | 0.12.41+57 | Fix the Jitsi XMPP WebSocket handshake: connect with the `xmpp` subprotocol (the server rejects connections without it with HTTP 501) and add on-screen connection diagnostics. |
| 2026-11-27 | 0.12.40+56 | Removed the Jitsi WebView fallback and `flutter_inappwebview`: calls use only the custom WebRTC screen; a failed connection now ends the call with a message. |
| 2026-11-27 | 0.12.39+55 | Custom WebRTC call screen (flutter_webrtc + Jitsi XMPP/Jingle, ported from InfinityOne ISP-2194) with mute/camera/speaker/switch controls; falls back to the Jitsi web view if the connection cannot be established. |
| 2026-11-27 | 0.12.38+54 | Request microphone/camera permissions before the native Jitsi join (the SDK starts a mic foreground service) and fall back to the WebView when the native conference drops with an error within 45s. |
| 2026-11-27 | 0.12.37+53 | Pin `jitsi_meet_flutter_sdk` 12.1.5 (matching the 2.0.11031 server) for the native Jitsi call UI, with automatic WebView fallback when the SDK cannot connect. |
| 2026-11-27 | 0.12.36+52 | Full-screen Jitsi call UI (our AppBar removed) so the call looks like the Jitsi app; only a small floating back button remains. |
| 2026-11-27 | 0.12.35+51 | Leaving a call from Jitsi's own hangup button is detected in the WebView and ends the call for both sides; the other device closes its call screen immediately. |
| 2026-11-27 | 0.12.34+50 | Pass the Jitsi JWT in both the URL query and hash; WebViews that drop the fragment no longer show "Authentication required". |
| 2026-11-27 | 0.12.33+49 | Calls now run the Jitsi web app inside an in-app WebView (native Jitsi SDK removed after "You have been disconnected"); mic/camera permissions requested in-app, browser fallback when the WebView cannot render, APK back to ~27 MB. |
| 2026-11-27 | 0.12.32+48 | Call liveness: while in a call the app sends `/calls/{id}/heartbeat`; the backend ends answered calls silent for 3 minutes, dismisses stale CallKit UI on launch, and hangs up Jitsi when the other side ends the call. |
| 2026-11-27 | 0.12.31+47 | Fix call start failing (push queue rejected NULL notification) and blank Jitsi screen (release build now unminified); Jitsi token `sub` matches the working webcasting token (`jitsi.ckamal.com`). |
| 2026-11-27 | 0.12.30+46 | Call polish: outgoing call notification is marked connected while in Jitsi and cleared when the call ends. |
| 2026-11-27 | 0.12.29+45 | Voice/video calls via Jitsi (`jitsi.ckamal.com`): 1:1 calls ring through CallKit/full-screen notification, group calls only show an in-chat banner with join, Log Telepon filled with call history and call-back, mic/camera permissions. |
| 2026-11-27 | 0.12.28+44 | Chat menus in list + room (pin, mute, clear all, add contact, delete/leave), group notification mute, pin/mute icons by the name, wider name layout, logout exits app, login password visibility toggle. |
| 2026-11-27 | 0.12.27+43 | Pin/unpin personal and group chats; business availability requires owner personal online and hides inactive businesses from the map; UI polling pauses in background while GPS/WebSocket stay connected. |
| 2026-11-27 | 0.12.26+42 | Opening a chat marks that conversation read (incl. cached messages) and clears only its notification; chat list reloads on app resume; personal online dots derive from recent location/presence (2 min); business status dots reflect `is_active`. |
| 2026-11-27 | 0.12.25+41 | Reactions/copy on long-press, per-user/full message delete, group last-sender preview, compact bubble timestamps, faded deleted text, online/active dots for personal+business accounts in chat/contacts, login/settings cleanup, and chat badge suppression while on Chat tab. |
| 2026-11-27 | 0.12.24+40 | Release build: notification channel with sound/high priority; direct typing shows no name; chat scrolls above keyboard; touch sound + bubble fade/slide animation; full-bleed chat list; message status ticks (clock/sent/delivered/read); optimistic sending; long-press delete for me/everyone. Signed with debug key for internal testing. |
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
- **Connection retry:** when a stored session cannot reach the server (e.g. right
  after the screen wakes up), the retry screen auto-retries every 3 seconds; do
  not log the user out for network errors.
- **Battery:** map, chat-list, badge, and fallback chat polling pause while the
  app is backgrounded; GPS/presence tracking and WebSocket stay connected.
  Polling resumes and data refreshes on foreground.
- **Chat badge:** never show the bottom Chat badge while the Chat tab is
  selected; chat notifications received while the Chat tab is active are marked
  read (also when leaving the tab). Opening a conversation marks only that
  conversation's chat notifications read; resume reloads the chat list.
- **Active dots:** chat list, chat header, and contacts show a green dot at the
  avatar's top-right for active/online accounts (personal uses `is_online`,
  business uses `is_active`), grey otherwise.
- **Chat cache:** messages are cached per conversation in `ChatCache`; opening a
  chat uses the cache and only fetches messages after the last cached id. Clear
  the cache on logout, clear-chat, and delete/leave.
- **Typing label:** direct chats show only “sedang mengetik…”; groups include the
  typing member names. Keep the keyboard from hiding the last message by
  scrolling to the bottom when input focus/metrics change.
- **Message feedback:** play `MessageSound` for new incoming/sent messages and
  animate newly added bubbles once (fade + slide). Suppress the chat-list sound
  when that conversation is already open (`ChatPresence`).
- **Reactions/copy:** long-press any message opens the emoji row, “Salin pesan”
  (text only), and delete options for own messages. Reaction counts render as
  chips below the bubble; tapping a chip toggles it.
- **Message delete:** long-press an own message → “Hapus untuk saya”
  (`sek_message_hidden`, per user) or “Hapus untuk semua” (soft delete + WS
  `message.deleted`, bubble becomes “Pesan ini dihapus”).
- **Message status:** outgoing bubbles show clock (pending), one check (sent),
  double check (delivered), double check blue (read). Sending inserts an
  optimistic pending bubble immediately; replace it with the server message.
  `messages.delivered` and `read.updated` WS events update counts.
- **Chat list styling:** full-bleed rows with no card radius or side padding;
  use dividers between rows.
- **Pin:** personal and group chats can be pinned per user from the three-dot
  menu (`conversations/{id}/pin`); pinned chats sort first and show a pin icon
  next to the name. Group mute (`/mute`) suppresses chat notifications.
- **Calls:** 1:1 voice/video calls ring through CallKit (`flutter_callkit_incoming`)
  and open the custom WebRTC call screen; group calls never ring, they only publish an
  `active_call` marker on the group. Join uses a short-lived JWT minted by the
  backend; never commit the Jitsi secret. Primary call path is the custom
  WebRTC screen (`lib/services/jitsi/`, flutter_webrtc + Jitsi XMPP/Jingle).
  There is no WebView fallback.
- **Chat actions:** the three-dot menu exists in both the chat list and chat
  room (pin, mute for groups, clear all, add contact for unknown personal
  peers, delete/leave). Logout exits the app instead of showing login; login
  password has a visibility toggle.
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
