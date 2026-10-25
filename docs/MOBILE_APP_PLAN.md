# Mobile App (React Native) — Plan

> **Status: proposal.** Companion to [MOBILE_API_PLAN.md](MOBILE_API_PLAN.md). The app
> talks only to the Rails API (`/api/v1`). Decisions marked **(decide)** are open; each has a
> recommendation.

Goal: an iOS + Android app with every player-facing feature of the web app — seasons
and the battle pass, workouts and Strava, challenges, events, clubs, achievements,
profile and cosmetics, support. **Nothing from `/admin`**, and no season sandbox. The
web app stays as it is; the app is a second way into the same accounts and data.

---

## 1. Stack

**Selection rule: in every category, use the library most used by the React Native
community.** "Most used" means npm weekly downloads, checked against the State of React
Native survey. A less popular library is picked only when the popular one is
unmaintained or doesn't work with Expo, and the table says so. Re-check the downloads
when the project starts (`npmtrends.com`), since rankings move.

| Concern | Choice | Why it's the community default | Close alternative |
|---|---|---|---|
| Framework | **Expo + TypeScript**, Continuous Native Generation (`expo prebuild`) | The framework React Native's own docs recommend; most new apps start on it | Bare React Native CLI |
| Navigation | **React Navigation** (native stack + bottom tabs) | The most-downloaded navigation library (Expo Router is built on it). Its `linking` config maps web paths (`/seasons/:id`) to screens (§5) | Expo Router |
| HTTP | **axios**, with types generated from `openapi/v1/openapi.yaml` by **openapi-typescript** | axios is the most-used HTTP client; its interceptors are the standard place for token refresh. openapi-typescript is the most-downloaded OpenAPI→TS generator | openapi-fetch, orval |
| Server state | **TanStack Query** | The most-used data-fetching/cache library in React and React Native | RTK Query, SWR |
| Client state | **Redux Toolkit** (session, preferences, offline queue), kept small | The most-used state library by downloads. Zustand scores higher on satisfaction; switch if the team prefers it, since almost all state here is server state anyway | Zustand |
| Forms | **react-hook-form** + **zod** | The most-used form library and the most-used schema validator | Formik + Yup |
| Styling | **NativeWind** (Tailwind for RN), tokens ported from [application.css](../app/assets/tailwind/application.css) | The most-used styling library beyond the built-in `StyleSheet`, and the team already writes Tailwind | Tamagui, styled-components |
| Icons | **@expo/vector-icons** (Font Awesome set) | The most-used icon package; the web already uses Font Awesome (`fa-solid …`), so the icons match | react-native-vector-icons |
| Lists | **@shopify/flash-list** | The most-used third-party list (built-in `FlatList` for short lists) | FlatList |
| Images | **expo-image** | The most-used maintained image component (react-native-fast-image is unmaintained) | — |
| Animation | **react-native-reanimated** + **lottie-react-native** | Most used for animations and for celebratory animations, respectively | Moti |
| Gestures, sheets | **react-native-gesture-handler**, **@gorhom/bottom-sheet** | The defaults for gestures and bottom sheets | — |
| Safe areas, SVG, gradients | **react-native-safe-area-context**, **react-native-svg**, **expo-linear-gradient** | Standard in nearly every app | react-native-linear-gradient |
| Persistent storage | **@react-native-async-storage/async-storage** (query cache via TanStack's AsyncStorage persister, preferences); **expo-secure-store** (refresh token) | AsyncStorage is the most-downloaded storage library; secure-store is the Expo default for Keychain/Keystore | react-native-mmkv |
| Dates | **date-fns** (+ `date-fns-tz` for the season time zone) | The most-downloaded date library | Day.js |
| i18n | **i18next** + **react-i18next** + **expo-localization**; **en** and **pt** | The most-used i18n stack | react-intl |
| Toasts | **react-native-toast-message** | Most used for toasts | — |
| Push | **expo-notifications** | The default for Expo apps (§6) | @react-native-firebase/messaging |
| Auth sessions | **expo-web-browser** (`openAuthSessionAsync`) | The Expo default for OAuth / web flows (Strava, forgot password) | react-native-app-auth |
| Media | **expo-image-picker** + **expo-image-manipulator** | Expo defaults; resize/compress before upload (≤ 1600 px, JPEG ~0.8), well under the 5 MB limit | react-native-image-picker |
| Analytics | **posthog-react-native** | PostHog is already the web's analytics, so web and app share one funnel | Firebase Analytics |
| Errors | **@sentry/react-native** | The most-used crash/error reporter for RN | Firebase Crashlytics |
| Unit / component tests | **Jest** + **React Native Testing Library**; **MSW** for API mocks | The most-used test runner, component testing library and mocking library | — |
| End-to-end tests | **Detox** | The most-adopted RN-specific e2e framework | Maestro (simpler YAML flows, growing fast) |
| Build & release | **EAS Build / Submit / Update** | The standard build/OTA pipeline for Expo apps | Fastlane + CodePush (CodePush is retired) |

Repository (decide): *recommendation* **monorepo** folder `mobile/` in this repo, so
the generated types are rebuilt in the same PR that changes `openapi.yaml`.

```
mobile/
  App.tsx
  src/
    navigation/   # React Navigation: RootStack, AuthStack, Tabs, linking.ts (web path ↔ screen)
    screens/
      auth/       # Welcome, Login, Register
      season/     # SeasonHome, Pass, SeasonChallenges, Leaderboard, Activity, SeasonsList
      workouts/   # WorkoutsList, LogWorkout, StravaImport
      explore/    # ChallengesList, ChallengeDetail, Timeline, Invite, EventsList, EventDetail
      community/  # ClubsList, ClubDetail, NewClub
      profile/    # Profile, EditProfile, Locker, Achievements, Integrations, Settings
      support/    # TicketsList, NewTicket, TicketThread
    api/          # openapi-typescript output (generated) + axios instance (auth, locale, idempotency) + query hooks
    store/        # Redux Toolkit slices: session, preferences, offlineQueue
    components/   # design system: Card, ProgressBar, RarityChip, FramedAvatar, ProfileBanner…
    features/     # per-feature hooks and pieces (season/, workouts/, locker/…)
    i18n/         # en.json, pt.json
    theme/        # tokens, season themes, cosmetic render map
  e2e/            # Detox specs
```

---

## 2. Information architecture

Five tabs. The app builds its menu from `GET /api/v1/config` → `features`, which lists
only the features that are switched on (key, localised name, description and a
FontAwesome6 icon name), in menu order. A tab or entry point whose feature isn't listed
is hidden. A deep link into one of `unavailable_features` shows a friendly
"<name> is unavailable" screen instead of an error.

Keeping it current: every API response carries an `X-Features-Version` header. When it
differs from the `features_version` the app last saw, the app refetches `/config` (sending
`If-None-Match`, so an unchanged menu costs a 304) and the tabs update. A 403 with
`error.code = "feature_disabled"` names the feature in `error.feature`, so a screen that
was open when an admin switched it off can close itself.

| Tab | Content | Web equivalent | Feature flag |
|---|---|---|---|
| **Season** (default) | Active season home; archive of the last season | `seasons#show` is the web's signed-in home | `seasons` |
| **Workouts** | History, log a workout, import from Strava | `workouts#*` | `workouts` |
| **Explore** | Challenges and events, segmented | `challenges#*`, `events#*` | `challenges`, `events` |
| **Community** | Clubs list, my clubs, club page | `clubs#*` | `clubs` |
| **Profile** | Profile + stats, locker, achievements, integrations, support, settings | `profiles#*`, `appearances#*`, `achievements#*`, `integrations#*`, `support_*` | `achievements`, `integrations`, `support` (rows) |

Unauthenticated stack: Welcome → Log in / Create account. "Forgot password" opens the
existing **web** reset page in an auth session (the API plan keeps reset on the web).

---

## 3. Screens

Each screen lists the endpoints it uses (from §10 of the API plan) and what needs care.

### Auth
| Screen | Endpoints | Notes |
|---|---|---|
| Welcome | — | Brand, season artwork, Log in / Create account |
| Log in | `POST /api/v1/auth/login` | Shows the locked-account message (Devise lockable parity: 20 attempts → unlock email or 1 h) |
| Create account | `POST /api/v1/auth/register` | First/last name, nickname, email, password (6–128), optional avatar after sign-up |
| Forgot password | `POST /api/v1/auth/password` → web page | Opens the reset link flow on the web |

### Season (the heart of the app)
The web page is one long scroll with ~12 sections. On a phone that is too much, so the
season home keeps the "what do I do today" parts and links out to the rest:

| Screen | Sections (from [seasons/show](../app/views/seasons/show.html.erb)) | Endpoints |
|---|---|---|
| **Season home** | Themed header (season theme gradient or image), my level + XP bar, **unclaimed XP panel** with Claim / Claim all, today's **dailies**, the next special event (countdown), community goal progress | `GET /api/v1/seasons/:id`, `/dailies`, `/community`, `GET/POST /claims` |
| **Pass** | Battle pass track (free/premium per level, horizontally scrolling), bonus reward tracks (legacy, completion tiers, medals, community), reward claim | `/rewards`, locker claim |
| **Challenges** | Grouped by category; weeklies by week with per-requirement medals; specials marked; objectives and legacy missions; locked-until-level state; date windows | `/challenges`, `/objectives` |
| **Leaderboard** | Board switcher (`?board=`), top N, my position pinned | `/leaderboard` |
| **Activity** | Recent season activity feed | `/activities` |
| **Seasons list** | Active + the one archived season (`browsable` rules) | `GET /api/v1/seasons` |

Claim UX: optimistic animation (orb flies into the XP bar, number counts up, level-up
celebration), then reconcile with the server response. A double tap is harmless — the
request carries an `Idempotency-Key` and the server guards the claim.

After a workout is logged, XP is credited asynchronously (API plan §4.1): the season
home shows "calculating XP…" and refetches the participation a few seconds later (or
on the "+XP" push).

### Workouts
| Screen | Endpoints | Notes |
|---|---|---|
| History | `GET /api/v1/workouts` (cursor) | Sport icon, distance, duration, pace, source (manual/Strava) |
| Log workout | `POST /api/v1/workouts` | Sport, date, optional start time (without it the workout can't count for hour-based challenges — say so in the form), distance (km + m), duration (h/m/s). **Works offline**: queued with its idempotency key and sent when back online |
| Strava import | `GET /api/v1/strava/activities`, `POST /api/v1/strava/import` | Preview list, import selected/all; progress state while the Rails importer runs |

### Explore
| Screen | Endpoints | Notes |
|---|---|---|
| Challenges list / detail | `GET /api/v1/challenges`, `/:id`, `POST /:id/join` | Requirements with progress |
| Invite | `GET /api/v1/challenges/:id/invite` | Native share sheet with the invite link (opens the app via universal link, or the web) |
| Timeline | `GET/POST /api/v1/challenges/:id/timeline`, comments | Posts with multiple images (direct uploads, attached by signed id), comments; **report / block** (§7) |
| Events list / detail | `GET /api/v1/events`, `/:id` | Image, date, location, distances |
| Event participation | `POST/PATCH/DELETE /api/v1/events/:id/participation` | Pick a distance; add result after the event |

### Community
| Screen | Endpoints | Notes |
|---|---|---|
| Clubs list / detail | `GET /api/v1/clubs`, `/:id` | Members, my membership |
| Create club | `POST /api/v1/clubs` | |
| Join / leave | `POST /api/v1/clubs/:id/join`, `DELETE …/membership` | Joining can complete a season objective — show it when the participation refreshes |

### Profile
| Screen | Endpoints | Notes |
|---|---|---|
| Profile | `GET /api/v1/me`, `/api/v1/me/stats` | Banner + framed avatar + coloured name (equipped cosmetics), title, stats (distance, week streak, workouts, seasons, medals), season medal shelf |
| Edit profile | `PATCH /api/v1/me`, `POST /api/v1/uploads` + `PATCH /api/v1/me {avatar: signed_id}` | Names, nickname, title (earned only), sports, optional personal fields, email reminders toggle |
| Locker | `GET /api/v1/me/locker?kind=`, equip/unequip, claim | Banners, frames, name colours, borders; owned vs locked; rarity chips |
| Achievements | `GET /api/v1/achievements` | Medals per season, badges |
| Integrations | `GET /api/v1/integrations`, Strava connect/disconnect | §6 |
| Support | tickets list / new / thread | Ticket threads with the team |
| Settings | `PATCH /api/v1/me` (locale, email reminders), notification permission, log out, **delete account** (`DELETE /api/v1/me`) | Account deletion is mandatory on the App Store |

---

## 4. Design system

- **Tokens:** port `--color-*` from `application.css`. React Native has no `oklch()`, so
  tokens are converted to hex once at build time (a small script reads the CSS and writes
  `theme/tokens.ts`); light and dark palettes, following the system setting.
- **Season themes** (`default summer winter spring autumn legacy`): gradient stops as
  data in `theme/seasons.ts`, rendered with `expo-linear-gradient`; a season image, when
  present, sits under a scrim exactly like the web header.
- **Cosmetics:** `banner` and `frame` are pictures (CDN URLs). `name_color` and `border`
  are **CSS classes on the web**, which a native app can't use. **In the API plan (§10):** the
  cosmetic payload carries render data (`{type: "solid"|"gradient", colors: [...]}`)
  instead of class names; the web helper and the API read the same definitions.
- **Rarity:** common / rare / epic / legendary colours for chips and borders, shared with
  the web via the same definitions.
- **Components:** Card, ProgressBar (animated), RequirementRow (with medal tier), XPOrb,
  RarityChip, FramedAvatar, ProfileBanner, CountdownBadge, EmptyState, ErrorState.
- **Accessibility:** Dynamic Type / font scaling, VoiceOver/TalkBack labels on every
  icon button, 44 pt minimum hit targets, reduced-motion turns the claim animation into a
  simple fade.

---

## 5. Networking, auth and offline

- **axios instance** (used by every query hook) adds: `Authorization: Bearer <access>`,
  `Accept-Language` (app locale), `X-App-Version`, and an `Idempotency-Key` on POSTs.
- **Tokens:** access JWT in memory only; rotating refresh token in `expo-secure-store`.
  A single in-flight refresh on `401` (axios response interceptor); if refresh fails → back to Log in. Logout calls
  `/api/v1/auth/logout` and wipes secure store + query cache.
- **Forced update:** on launch `GET /api/v1/config`; below `min_supported_version` → blocking
  "Update the app" screen. JS-only fixes ship through EAS Update within the same runtime.
- **Offline:** TanStack Query cache persisted to AsyncStorage, so the last season/workouts/profile
  render instantly and offline. Writes are online-only except **log workout**, which is
  queued and retried with its idempotency key (no duplicates if the first attempt did
  land).
- **Links:** React Navigation's `linking` config maps the web paths to screens, and the app is registered for **universal
  links / app links** on the web domain (`apple-app-site-association`,
  `assetlinks.json` served by Rails). A shared season, event or challenge-invite link
  opens the app if installed, the web otherwise. Push payloads keep today's `path`
  (`/seasons/12`), which the app routes directly.

---

## 6. Native integrations

**Push notifications (decide).**
*Recommendation:* **Expo Push Service** for v1 — the app registers an Expo push token
(`POST /api/v1/devices {platform: "expo", token}`) and Rails' `PushNotifier` sends to Expo's
HTTP API, which handles APNs and FCM credentials. Simpler than running FCM for iOS
(raw FCM on iOS needs the Firebase SDK). API plan §8 is written for Expo.
- Ask for permission at a meaningful moment (after the first workout, or on joining a
  season), never on first launch; explain what will be sent (XP, level up, new season,
  special events).
- Tapping a notification routes to its `path`; `tag` collapses repeats (e.g. bulk Strava
  import XP).

**Strava.** "Connect Strava" → `POST /api/v1/strava/authorize` → `openAuthSessionAsync` with
Strava's **mobile authorize URL** (it hands off to the Strava app when installed) →
redirect to the app's universal link → `POST /api/v1/strava/callback {code, state}`. The
client secret never leaves the server.

**Image uploads.** Pick → resize/compress → `POST /api/v1/uploads` (direct-upload slot + `signed_id`) → `PUT` to
storage with progress → attach by `signed_id` (`PATCH /api/v1/me {avatar}` or a timeline post's `images`).
Failed uploads can be retried without re-picking.

**Later (post-v1):** Apple Health / Google Health Connect as a workout source — a big
win on mobile for players without Strava. Needs an API provider (`healthkit`,
`health_connect`) and the same normalisation as manual workouts.

---

## 7. Store requirements (things the web never needed)

| Requirement | Plan |
|---|---|
| **In-app account deletion** (Apple 5.1.1(v), Google Play) | Settings → Delete account → `DELETE /api/v1/me` (already in the API plan) |
| **User-generated content** (Apple 1.2): timeline posts, comments, club names | **New:** report content, block user, hide blocked users' content; the team reviews reports (Rails admin). **In the API plan (§10):** `POST /api/v1/reports`, `POST/DELETE /api/v1/blocks/:user_id`, plus tables and an admin queue |
| Privacy labels / Data safety form | Declare: email, name, optional phone/document/blood type/address, workouts, photos, analytics (PostHog), crash data (Sentry). No tracking → no ATT prompt |
| Sign in with Apple | Not required while email/password is the only login (Strava is an integration, not a login). Required if social login is ever added |
| Privacy policy + terms URLs | Linked from Welcome and Settings (pages on the web) |
| Sensitive optional fields (`document`, `blood_type`) | Keep optional, explain why they're asked; consider leaving them web-only |

---

## 8. Quality

- **Unit / component:** Jest + RNTL for components and hooks; MSW handlers generated from
  OpenAPI, so every screen is tested against realistic payloads, including errors and
  feature-disabled responses.
- **End-to-end:** Detox specs run on CI simulators for: sign up → log workout → see XP;
  claim XP; equip cosmetic; join club; event participation; Strava connect (stubbed);
  delete account.
- **Contract:** CI regenerates the types from `openapi/v1/openapi.yaml` (openapi-typescript); `tsc` must pass.
- **Localisation:** CI fails on keys missing in either `en.json` or `pt.json`; a
  pseudo-locale build catches truncation.
- **Release health:** Sentry crash-free sessions ≥ 99.5 % before widening a rollout;
  staged rollout on Play, phased release on App Store.

---

## 9. Phases

Aligned with the API plan's phases (the app can't run ahead of its endpoints; MSW mocks
let UI work start earlier).

| Phase | Scope | Depends on API phase | Exit criteria |
|---|---|---|---|
| **M0 — Setup** | Expo project, React Navigation + linking, NativeWind tokens, generated API types + axios instance, Redux store, Sentry, PostHog, EAS profiles (dev/preview/prod), CI | API 1 (first `openapi.yaml`) | Dev build on both platforms from CI |
| **M1 — Auth + shell** | Welcome, log in, register, forgot password, tabs, `/api/v1/config` flags, forced update, settings, log out | API 1 (auth) | A real account logs in on mobile and web |
| **M2 — Read everything** | Season home/pass/challenges/leaderboard/activity, workouts history, challenges, events, clubs, profile, achievements, support (read) | API 2 (reads + CDN images) | Every screen shows the same data as the web for a test account |
| **M3 — Writes** | Log workout (offline queue), profile edit + avatar, clubs, events participation, timeline posts/comments with images, support tickets, delete account, report/block | API 3 | Workout logged on mobile shows XP on web; images upload through the CDN |
| **M4 — Claims & locker** | XP claim with animation, reward claim, locker equip/claim, cosmetics rendering | API 4 | Claiming on mobile and web gives identical results; no double claims |
| **M5 — Strava + push** | Strava connect/import, push registration and routing, universal links | API 5 | Connect + import on device; push tap opens the right screen |
| **M6 — Beta & launch** | TestFlight + Play internal testing, accessibility pass, store listings, privacy forms, staged rollout | API 6 | Store approval; crash-free ≥ 99.5 % in beta |

---

## 10. Requests this plan made of the API plan

All five are now part of [MOBILE_API_PLAN.md](MOBILE_API_PLAN.md):

1. **Push via Expo Push Service**: API plan §8.
2. **Cosmetic render data** (`name_color` / `border` as colours/gradients): API plan §10.
3. **Moderation** (report content, block user, admin review queue): API plan §10.
4. **Universal links** (`apple-app-site-association`, `assetlinks.json`; the Strava
   redirect points at an app link): API plan §9 and §10.
5. **`GET /api/v1/me/stats` and the season's "next special event"**: API plan §10.

---

## 11. Open decisions

1. **Push provider:** Expo Push Service (*recommended*) vs direct FCM/APNs.
2. **Repo:** `mobile/` in this monorepo (*recommended*) vs separate repo.
3. **Personal fields** (`document`, `blood_type`, `address`, `phone`) on mobile, or
   web-only (*recommended: web-only for v1* — less to declare in privacy forms).
4. **Premium track:** if the season's premium pass is ever sold in-app, Apple/Google
   require in-app purchase (RevenueCat would be the usual route). Today there is no
   purchase flow (`SeasonParticipation#grant_premium!` has no caller), so v1 only
   displays the premium track.
5. **App name and bundle ids** (`Broken Wheels`?), and who owns the Apple Developer /
   Google Play accounts.
