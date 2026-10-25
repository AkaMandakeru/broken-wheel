# Mobile API (Rails) — Plan

> **Status: built (phases 0–5), not yet deployed.** All of §10 is implemented under
> `/api/v1`, with request specs that generate [openapi/v1/openapi.yaml](../openapi/v1/openapi.yaml).
> What's left is operational (§3 rows 0.1 and 0.6, CDN and env setup, see §14) and the
> open decisions in §13.
>
> Replaces the earlier Go API plan. The API lives **inside this Rails app**, under
> `/api/v1`, and reuses the existing models, services, jobs and specs.

Goal: ship iOS/Android apps ([MOBILE_APP_PLAN.md](MOBILE_APP_PLAN.md)) backed by a JSON
API that covers every player-facing feature. The web app, the admin panel and the API
are one codebase on one PostgreSQL database, with **no data loss** and no second
implementation of the season engine.

Out of scope for the API: everything under `/admin`, the season sandbox, blueprint
import/export, and Slack/analytics configuration.

---

## 1. Why Rails instead of Go, and what that removes

The Go plan was mostly about **keeping two applications consistent** on one database.
With one application, most of that work goes away:

| Go plan needed | With the API in Rails |
|---|---|
| `domain_events` outbox + `OutboxDispatcher` so Rails could react to Go's writes | **Gone.** Model callbacks (`Workout#after_create_commit`, `ClubMembership`, `SeasonParticipation`, `User#after_create`…) fire as they do on the web |
| Porting XP claims, reward claims, equip, wallet and challenge join to Go, plus a parity suite in both languages | **Gone.** Controllers call `SeasonXpClaimer`, `SeasonRewardClaimer`, `Wallet`, `ChallengeEnroller` and `User#equip_cosmetic!` directly |
| Daily draw kept in Rails because Go can't reproduce `Random.new(seed).sample` | **Gone.** `DailyChallenges::Assigner` runs inline when a player has no assignment yet |
| Porting `Workout` normalisation, `minute_of_day_from`, `WorkoutStreak`, `SeasonLeaderboard` SQL, i18n loading and `display_title` | **Gone.** Same Ruby, same `config/locales/*.yml` |
| Separate DB credential, connection budget, schema dump and `sqlc` CI | **Gone.** One pool and one `db/schema.rb` |
| Images off Active Storage because Go can't read it | **Not needed.** See §5: Active Storage stays, with a CDN in front |
| bcrypt and Devise lockable reimplemented in Go | **Gone.** The API calls Devise's own `valid_for_authentication?` |

What's still real work:
- **Logic hidden in web controllers** (`seasons#show` `load_*`, `profiles#load_stats`,
  `workouts#index`) has to move into objects that both HTML and JSON can use (§4.2).
- **Production background jobs aren't durable** (§3). The web has the same problem today.
- **Mobile-only concerns:** token auth, native push, Strava OAuth from an app,
  idempotent retries, versioning, store requirements.

---

## 2. Platform: Ruby 4.0 and Rails 8.1

### Done in this change

| | Before | Now |
|---|---|---|
| Ruby | 4.0.1 | **4.0.9** (latest stable; `.ruby-version`, `Dockerfile`, and `ruby file: ".ruby-version"` in the Gemfile so Heroku uses the same version) |
| Rails | 8.1.2 | **8.1.4** (latest; 8.2 isn't released) |
| Gems | — | `bundle update --all`: Devise 5.0.4, Puma 8.0.2, Solid Queue 1.7, Solid Cable 4.1, json 3.1, pg 1.7, aws-sdk-s3, posthog-ruby, rubocop… |
| Rack deprecation | `:unprocessable_entity` | `:unprocessable_content` everywhere |

678 specs pass; Brakeman and bundler-audit are clean. Ruby 4.1 is only at preview 1; move
to it after its stable release (normally 25 December) plus a patch release.

### Ruby features: what we use and what we don't

| Feature | Decision | Why |
|---|---|---|
| **YJIT** | **On in production** | Rails turns it on automatically (`config.yjit`, a default since 7.2). The official Docker and Heroku Rubies are built with it. Check `RubyVM::YJIT.enabled?` in a production console after deploy, and watch memory (YJIT adds some). |
| **ZJIT** (the new method JIT in 4.0) | **Not in production yet** | Experimental in 4.0. Benchmark it in staging when 4.1 ships; YJIT is still the production JIT. |
| **Ractors** | **Not used** | Ruby 4.0 improved them (`Ractor::Port`, shareable procs, less lock contention), but they're still experimental, and Rails, Active Record, the `pg` driver, Devise and most gems aren't Ractor-safe: autoloading, connection pools and global config all use shared mutable state. More importantly, the workload here is I/O-bound: almost every request waits on Postgres, and Puma threads already release the GVL while they wait. Ractors would add risk and gain nothing. Revisit only for a pure-Ruby, CPU-bound job with no Active Record inside, which this app doesn't have today. |
| **Fiber scheduler / Falcon** | **Not used** | Same reason: Puma threads plus Postgres is the supported, measured path. Long outbound calls (Strava, Expo push) already run in jobs, not in requests. |
| **`Ruby::Box`** (namespaces) | **Not used** | Experimental, and solves a problem we don't have. |
| **`Data.define`** | **Use** for new value objects in the API (cursor, upload slot, auth result) | Immutable, keyword-friendly, and works with pattern matching. Existing `Struct` results like `SeasonXpClaimer::Result` stay as they are. |
| **Pattern matching** (`case … in`) | **Use** in API controllers to branch on service results | Easier to read than nested `if`s on result predicates. |
| **jemalloc** | Already in the Dockerfile | On Heroku, add the jemalloc buildpack or set `MALLOC_ARENA_MAX=2`. |

### Rails 7.1–8.1 features this plan relies on

| Feature (version) | Used for |
|---|---|
| `ActionController::API` | Lean base for `/api/v1`: no cookies, sessions, CSRF, views, or `allow_browser` (which would block native clients) |
| `generates_token_for` / `find_by_token_for` (7.1) | Signed, expiring access tokens with instant revocation (§6). No JWT gem. |
| `rate_limit` (7.2) | Throttling login, register, password reset and uploads per IP/user |
| `params.expect` (8.0) | Strict parameter shapes in every API controller |
| **Solid Queue / Solid Cache** (8.0) | Durable jobs and a shared cache (the cache that `rate_limit` needs) without Redis |
| **Active Job Continuations** (8.1) | Long jobs that resume after a restart: full Strava history import, storage copy (§5), season finalize fan-out. Heroku restarts dynos daily, so this matters. |
| **Structured event reporting** `Rails.event` (8.1) | One structured event per API action (`api.workout.created`, `api.claim.xp`…), tagged with user, app version and request id, sent to logs and PostHog |
| **Local CI** `config/ci.rb` (8.1) | One CI definition: RSpec, OpenAPI drift check, Brakeman, audit |
| **Deprecated associations** (8.1) | Contracting web-push code safely later (`has_many :push_subscriptions, deprecated: true` logs every use before removal) |
| Query log tags | SQL comments with controller/action/`api_version`, so slow API queries show up in Postgres logs |
| Active Storage named + `preprocessed` variants (7.1) | Image sizes generated on upload, served through a CDN (§5) |
| HTTP caching (`fresh_when` / `stale?`) | ETags on read endpoints, so the app's `If-None-Match` revalidations return `304` cheaply |

Not adopted: the Rails 8 authentication generator. Devise already owns passwords,
lockable and reset emails for the web, and the API reuses it (§6).

---

## 3. Phase 0 — Prerequisites (do these first)

| # | Change | Why |
|---|---|---|
| 0.1 | Turn on point-in-time recovery or daily backups, and **rehearse a restore** into a scratch database | The safety net for every later step |
| 0.2 | **Solid Queue in production**: load `db/queue_schema.rb` (`config/database.yml` already declares the `queue` database on the same URL), set `config.active_job.queue_adapter = :solid_queue` and `config.solid_queue.connects_to`, add `worker: bin/jobs` to the `Procfile` (or `SOLID_QUEUE_IN_PUMA=1` while traffic is small) | Today `queue_adapter = :async` runs jobs in Puma threads, loses them on restart, and never fires [recurring.yml](../config/recurring.yml): daily challenges, weekly resets, community goals, email reminders |
| 0.3 | **Solid Cache in production** instead of `:memory_store` | `rate_limit` and cached reads must be shared across dynos and survive restarts |
| 0.4 | **Mission Control – Jobs** under `/admin` | Lets admins see failed, retried and recurring jobs |
| 0.5 | Fix [config/ci.rb](../config/ci.rb): it runs `bin/rails test`, but the suite is RSpec (`bundle exec rspec`) | CI currently runs none of the 678 specs |
| 0.6 | Connection budget: `(web dynos × RAILS_MAX_THREADS) + (worker threads) + Solid Queue supervisor` ≤ the plan's connection limit | Web and API now share the web dynos |

Exit criteria: the web app runs on Solid Queue for a week with daily challenges and
reminders firing on schedule, and Mission Control shows no stuck jobs.

---

## 4. Architecture

```
  iOS / Android ──HTTPS/JSON /api/v1──┐          Web browser ──HTML──┐
                                      ▼                              ▼
                     ┌──────────────── Rails app (one codebase) ─────────────────┐
                     │  Api::V1::* (ActionController::API)    Web + /admin       │
                     │        └───────── shared: models, services, queries ──────┘
                     │  Solid Queue worker: recalc · push (web + Expo) · email ·  │
                     │                      Strava sync · reminders              │
                     └──────────────┬──────────────────────────────┬────────────┘
                                    ▼                              ▼
                             PostgreSQL (live)          Object storage ◀── CDN (§5)
```

### 4.1 Business logic: one implementation

- Every write goes through the **same models and services** the web uses. Callbacks,
  validations, unique indexes and the idempotent recompute stay the single source of
  truth.
- **XP after a workout is still asynchronous.** `Workout#after_create_commit` enqueues
  the debounced `SeasonRecalcJob`, as it does on the web. `POST /api/v1/workouts` returns
  the workout plus `xp_pending: true`. The app shows "calculating XP…" and refetches the
  participation a few seconds later, or when the "+XP" push arrives. This needs Phase 0.2.
- **Daily assignment:** `AssignDailyChallengesJob` assigns everyone after midnight. For
  a player with no assignment yet (they joined today), `GET …/dailies` calls
  `DailyChallenges::Assigner` inline. It's the same draw the web would make.
- **Registration side effects** (PostHog `user_signed_up` + identify, Slack
  `user_registered`) live in `Users::RegistrationsController#after_sign_up_path_for`
  today. Move them into one `Accounts::Registration` service that both the Devise
  controller and the API call.

### 4.2 Sharing read logic between HTML and JSON

The web controllers build their pages from private `load_*` methods. Before each API
read is built, move that logic into a plain object both sides use:

| Today | Extract to | Used by |
|---|---|---|
| `seasons#show` → `load_challenges`, `load_dailies`, `load_objectives`, `load_rewards`, `load_leaderboard`, `load_community`, `my_challenge_progress`, `daily_progress`, `season_scope` | `Seasons::Dashboard` (one per section, memoised) | `SeasonsController#show`, `Api::V1::Seasons*Controller` |
| `profiles#load_stats` | `Profiles::Stats` | `ProfilesController`, `GET /api/v1/me/stats` |
| `workouts#index` filters/ordering | `Workouts::History` | both |
| `appearances#show` owned vs locked | `Locker::Catalogue` | both |

The existing request specs act as the regression guard: the web pages must stay green
while their logic moves.

### 4.3 Code layout

```
app/controllers/api/v1/
  base_controller.rb              # ActionController::API + concerns below
  auth/{sessions,registrations,passwords}_controller.rb
  me_controller.rb  locker_controller.rb  uploads_controller.rb  devices_controller.rb
  seasons_controller.rb  seasons/{challenges,dailies,objectives,rewards,activities,
                                  community,leaderboards,claims,announcements}_controller.rb
  workouts_controller.rb  strava_controller.rb  integrations_controller.rb
  challenges_controller.rb  challenges/{timeline_posts,comments}_controller.rb
  clubs_controller.rb  events_controller.rb  achievements_controller.rb
  support/{tickets,messages}_controller.rb  reports_controller.rb  blocks_controller.rb
  config_controller.rb
app/controllers/concerns/api/
  authentication.rb  error_handling.rb  idempotent.rb  paginated.rb  localized.rb  feature_guard.rb
app/resources/                     # Alba serializers: UserResource, SeasonResource…
app/queries/                       # Seasons::Dashboard, Profiles::Stats… (§4.2)
app/models/api_session.rb  device_token.rb  idempotency_key.rb  content_report.rb  user_block.rb
spec/requests/api/v1/**            # rswag request specs → OpenAPI
openapi/v1/openapi.yaml            # generated, committed, consumed by the mobile app
```

Routes: `namespace :api, defaults: { format: :json } { namespace :v1 { … } }` in
[config/routes.rb](../config/routes.rb), on the main domain. A single domain also serves
universal links (§9 of the app plan) and avoids CORS (native apps don't need it).

---

## 5. Images: Active Storage stays, with a CDN in front

**Change from the Go plan.** That plan moved images out of Active Storage and stored a
URL per column, mainly so Go could read images without Active Storage. With the API in
Rails, that reason is gone. Keeping Active Storage means no new `*_url` columns, no
backfill of references, no `timeline_post_images` table, and no rewrite of
`EngagementMailer#attach_banner` or the `SeasonChallenge` banner validation. **The app
still gets plain CDN URLs**, so nothing changes for the client.

### Target

1. **CDN in front of Active Storage's proxy routes.** A `direct :cdn_image` route
   builds proxy URLs on `CDN_HOST` (the pattern in the Rails Active Storage guide); API
   resources use it through `ImageUrls`. The web's own `image_tag`s are unchanged for
   now (they still use redirect routes), so `resolve_model_to_route` stays at its
   default. Cloudflare (or CloudFront) caches each original
   and variant once; Rails serves it once per edge. URLs are long-lived and keyed by
   blob, so they never go stale.
2. **Named, preprocessed variants** on each model, in place of the inline sizes in the
   views today (`resize_to_limit: [200, 200]`, `[800, 400]`, `[1000, 360]`…):
   avatar `thumb`/`medium`; challenge, event and season `card`/`hero`; cosmetic
   `display`; timeline images `thumb`/`large`. They're generated in a job right after upload, so
   the first view doesn't wait on libvips. Views and API resources ask for variants by
   name.
3. **Direct uploads from the app** (the same mechanism the web's direct uploads use):
   1. `POST /api/v1/uploads {purpose, filename, content_type, byte_size, checksum}`.
      The API checks the purpose (`avatar`, `timeline_post`), type (PNG/JPEG/WEBP/GIF)
      and size (≤ 5 MB, as `Season::MAX_IMAGE_BYTES`), then calls
      `ActiveStorage::Blob.create_before_direct_upload!`. It returns
      `{signed_id, direct_upload: {url, headers}}`.
   2. The app `PUT`s the bytes straight to storage. Rails never handles them.
   3. The app attaches by signed id: `PATCH /api/v1/me {avatar: signed_id}`, or
      `images: [signed_id…]` on a timeline post. Model validations re-check the
      analysed blob.
   4. A recurring job purges unattached blobs older than 48 hours.
4. **API resources** return `{ "original": url, "<variant>": url }`, built with `cdn_image`.

### Storage provider (decide)

The bucket can stay on Bucketeer/S3. *Recommendation:* move it to **Cloudflare R2**
(S3-compatible, no egress fees), with no downtime and no data loss:

1. Configure an Active Storage **`mirror` service**: primary = current `amazon`,
   mirror = `r2`. From then on, every new upload is written to both.
2. Run a **continuable job** (Rails 8.1 `ActiveJob::Continuable`) over
   `ActiveStorage::Blob.find_each`, calling `service.mirror(blob.key, checksum: blob.checksum)`.
   It resumes from its cursor after a restart and skips keys that already exist.
   This is `Storage::MirrorBlobsJob` (`r2` and a commented `mirror` are in
   config/storage.yml): once the service is `:mirror`, run
   `bin/rails runner 'Storage::MirrorBlobsJob.perform_later'` once.
3. Verify: compare object counts and checksums of a sample. Then flip the primary to
   `r2` with Bucketeer as the mirror for two weeks.
4. Remove the mirror, keep a bucket snapshot for 90 days, then retire Bucketeer.

Blob keys don't change, so the database doesn't change.

---

## 6. Authentication for mobile

- **Same accounts and passwords.** The login endpoint calls Devise directly:
  `user = User.find_for_authentication(email:)` then
  `user&.valid_for_authentication? { user.valid_password?(password) }`. That runs
  Devise's own lockable logic (attempt counter, lock, unlock email) and bcrypt (cost 12),
  so web and mobile behave identically.
- **Sessions:** a new `api_sessions` table (`user_id`, `refresh_token_digest`,
  `family_id`, `device_name`, `platform`, `app_version`, `last_used_at`, `expires_at`,
  `revoked_at`, `revoked_reason`). Each row is one refresh token: refreshing revokes the
  row (`rotated`) and creates the next one in the same family.
  - **Access token (15 min):** `ApiSession.generates_token_for(:access, expires_in: 15.minutes) { revoked_at }`.
    The token is signed by Rails' `secret_key_base` and is invalidated the moment the
    session rotates or is revoked. Each request makes one indexed lookup
    (`find_by_token_for(:access, token)`, which also loads the user). No JWT library and
    no key handling of our own.
  - **Refresh token (60 days, rotating):** opaque, stored as a SHA-256 digest. Each
    refresh issues a new one. If an already-used token is presented again more than 30
    seconds after its rotation, the whole `family_id` is revoked (theft detection); inside
    those 30 seconds it's treated as the app racing itself and just answered 401.
  - Logout revokes the session. A password change (web or API) revokes all of a user's
    sessions, via an `after_update_commit` on `encrypted_password`.
- **Registration:** `POST /api/v1/auth/register` → `Accounts::Registration` (§4.1).
  Default titles are granted by the existing `User#after_create`.
- **Password reset:** `POST /api/v1/auth/password` → `User.send_reset_password_instructions`.
  The email link opens the **existing web reset page**; Devise keeps owning the token.
- **Account deletion** (`DELETE /api/v1/me`, required by the App Store, guideline
  5.1.1(v)): lock the account, revoke sessions, answer 202 and enqueue
  `Accounts::DeletionJob`. `Accounts::Deletion` removes or reassigns every row that
  references the user (clubs pass to their longest-standing member) and then runs
  `user.destroy` with the existing `dependent:` rules.
- **Throttling:** `rate_limit to: 10, within: 3.minutes` on login/register/reset per
  IP, plus a per-email limit on login. Needs Solid Cache (Phase 0.3).
- **Later:** Sign in with Apple (required on iOS if any social login is added) and
  Google, using a `user_identities` table. Not needed for v1.

---

## 7. API conventions and tooling

| Concern | Choice |
|---|---|
| Base | `Api::V1::BaseController < ActionController::API`; bearer auth only (no cookies, so no CSRF surface) |
| Serialization | **Alba** resources in `app/resources/`. They're plain Ruby classes, testable, and much faster than Jbuilder templates. Jbuilder stays for the web's few JSON views |
| Contract | **OpenAPI 3.0.3 generated from request specs with rswag** (rswag doesn't support 3.1 yet) (`rswag-specs`). Each `spec/requests/api/v1/*` spec documents and tests an endpoint; `rake rswag:specs:swaggerize` writes `openapi/v1/openapi.yaml`. A CI step fails if the committed file differs from the generated one. The mobile app generates its TypeScript types from that file |
| Parameters | `params.expect(workout: [:sport, :started_on, :start_time, :distance_m, :duration_s])` |
| Errors | `rescue_from` in `Api::ErrorHandling`, giving `{"error": {"code", "message", "fields"}}` with a localised message. `RecordInvalid` → 422 with `errors.details`; `RecordNotFound` → 404; feature off → 403 `feature_disabled`; unsupported app version → 426 `upgrade_required` |
| Pagination | Cursor-based with **Pagy's keyset paginator** (`?cursor=&limit=`) on every list. The cursor is opaque and stable under inserts |
| Idempotency | `Idempotency-Key` header on POSTs that create or claim (workouts, claims, posts, uploads). An `idempotency_keys` table (`user_id`, `key` unique per user, `request_digest`, `status`, `body jsonb`) stores the first response; a retry replays it, and a different body with the same key gets 422. Pruned after 24 h by a recurring job |
| i18n | `Api::Localized` picks `user.locale`, then `Accept-Language`, then the default, and wraps the action in `I18n.with_locale`. Same `config/locales/*.yml` as the web |
| Feature flags | `GET /config` lists only the **available** features, in menu order, with a localised name, description and icon (`{set: "FontAwesome6", style, name}`, from the web's Font Awesome class), plus `unavailable_features` (key + name) for a friendly screen on deep links. Every response carries `X-Features-Version`; when it changes the app refetches `/config` (ETag, so usually a 304). Endpoints of a switched-off feature answer 403 `feature_disabled` with `error.feature` set to its key. `Api::FeatureGuard` reuses `Features::CATALOGUE` and `Current.disabled_feature_keys` |
| Caching | `stale?(etag: [record, current_user, I18n.locale])` on read endpoints; season reads also include the participation's `updated_at` |
| Versioning | `/api/v1`. Apps send `X-App-Version`; `GET /api/v1/config` returns `min_supported_version`, enabled features and locales. Breaking changes go to `/api/v2`; v1 controllers stay until the old builds are gone |
| Observability | `Rails.event.notify` per action, `request_id` in the response header, query log tags, Brakeman + bundler-audit in CI |
| Testing | rswag request specs (contract + behaviour) using the existing `spec/support/season_builders.rb`; a concurrency spec for double claims (two threads, one success) |

---

## 8. Push notifications for native apps

Web Push (VAPID) doesn't reach native apps. The app uses **Expo Push Service** (decision
in the app plan, §6):

- `POST /api/v1/devices {platform: "expo", token, app_version, locale}` /
  `DELETE /api/v1/devices/:token` → a new `device_tokens` table (`user_id`, `platform`,
  `token` unique, `app_version`, `locale`, `last_seen_at`).
- `PushNotifier.notify/broadcast` fans out to Web Push **and** a new
  `MobilePushDeliveryJob`, which posts batches of up to 100 to Expo's push API. Tokens
  that Expo reports as `DeviceNotRegistered` (from push receipts, checked by a follow-up
  job) are deleted, as `WebPushDeliveryJob` does for 404/410 today.
- The payload keeps `title/body/path/tag`. The app routes `path` (`/seasons/12`)
  directly.
- Every trigger (workout XP, level up, season start, event created, achievement) already
  calls `PushNotifier`, so no trigger changes.

---

## 9. Strava on mobile

- `POST /api/v1/strava/authorize` returns Strava's **mobile** authorize URL with a
  signed `state` (`Rails.application.message_verifier(:strava_state)`, 10 min, bound to
  the user) and a redirect to the app's universal link. The app opens it with
  `openAuthSessionAsync`.
- The app posts the code: `POST /api/v1/strava/callback {code, state}`. Rails exchanges
  it with the existing `StravaService` (the client secret never ships in the app),
  upserts `strava_tokens`, and enqueues the first `SyncStravaActivitiesJob`.
- `GET /api/v1/strava/activities` previews recent activities using the existing token
  refresh. Wrap `StravaService#refresh_token!` in `strava_token.with_lock`, so a request
  and a job never refresh at the same time (Strava invalidates the older refresh token).
- `POST /api/v1/strava/import` enqueues the sync. Make the full-history import an
  **Active Job Continuation**, so it resumes page by page after a restart.
- `DELETE /api/v1/strava` reuses `oauth#disconnect`'s logic.
- Later: Strava **webhooks** instead of polling.

---

## 10. API surface — v1

All paths are under `/api/v1`. Every endpoint reuses existing Ruby; the right-hand
column shows where.

| Feature | Endpoint | Reuses |
|---|---|---|
| Auth | `POST /auth/register` | `Accounts::Registration` (extracted from `users/registrations`) |
| | `POST /auth/login`, `/auth/refresh`, `DELETE /auth/logout` | Devise `valid_for_authentication?`, `ApiSession` |
| | `POST /auth/password` | `User.send_reset_password_instructions` |
| App config | `GET /config` (enabled features, locales, min supported version) | `Features::CATALOGUE`, feature flags |
| Me | `GET /me` (profile, coins, title, equipped cosmetics with **render data**, preferences) | `profiles#show` |
| | `GET /me/stats` (distance, week streak, workouts, seasons, medals) | `Profiles::Stats`, `WorkoutStreak` |
| | `PATCH /me` (names, nickname, sports, title, `email_reminders`, `locale`, `avatar: signed_id`) | `profiles#update` |
| | `DELETE /me` | `Accounts::DeletionJob` → `user.destroy` |
| Uploads | `POST /uploads` | `ActiveStorage::Blob.create_before_direct_upload!` |
| Locker | `GET /me/locker?kind=` | `Locker::Catalogue` |
| | `PUT /me/locker/:kind {key}`, `DELETE /me/locker/:kind` | `User#equip_cosmetic!` |
| | `POST /me/locker/claim` | `appearances#claim` logic, `SeasonRewardClaimer` |
| Seasons | `GET /seasons` | `browsable` scope |
| | `GET /seasons/:id` (header, my participation, level curve, announcement, next special event) | `Seasons::Dashboard` |
| | `GET /seasons/:id/challenges`, `/dailies`, `/objectives`, `/rewards`, `/activities`, `/community` | `Seasons::Dashboard`, `DailyChallenges::Assigner` (inline when unassigned) |
| | `GET /seasons/:id/leaderboard?board=` (top N + my position) | `SeasonLeaderboard` |
| | `GET /seasons/:id/claims`, `POST /seasons/:id/claims[/:completion_id]` | `SeasonXpClaimer` |
| | `POST /seasons/:id/announcement/dismiss` | `season_announcements#dismiss` |
| Workouts | `GET /workouts`, `POST /workouts` | `Workouts::History`, `Workout` callbacks |
| Strava | `GET /integrations`, `POST /strava/authorize`, `POST /strava/callback`, `DELETE /strava`, `GET /strava/activities`, `POST /strava/import` | `StravaService`, `SyncStravaActivitiesJob` |
| Challenges | `GET /challenges`, `GET /challenges/:id`, `POST /challenges/:id/join`, `GET /challenges/:id/invite` | `ChallengeEnroller` |
| | `GET/POST /challenges/:id/timeline`, `POST …/timeline/:post_id/comments` | `TimelinePost`, `TimelinePostComment` |
| Clubs | `GET /clubs`, `POST /clubs`, `GET /clubs/:id`, `POST /clubs/:id/join`, `DELETE /clubs/:id/membership` | `ClubMembership` callbacks → `SeasonObjectives` |
| Events | `GET /events`, `GET /events/:id`, `POST/PATCH/DELETE /events/:id/participation` | `EventParticipation` |
| Achievements | `GET /achievements` | `achievements#index` |
| Support | `GET/POST /support/tickets`, `GET /support/tickets/:id`, `POST /support/tickets/:id/messages` | `SupportTicket`, `SupportMessage` |
| Devices | `POST /devices`, `DELETE /devices/:token` | `DeviceToken` (§8) |
| Moderation | `POST /reports`, `POST/DELETE /blocks/:user_id` | New `content_reports`, `user_blocks` + an admin review queue (App Store guideline 1.2) |
| Email | unsubscribe stays a web link; the preference is in `PATCH /me` | `email_subscriptions#*` |

Additions that the app plan asked for, now part of this plan:
- **Cosmetic render data:** `name_color` and `border` are CSS classes on the web. The API
  returns `{type: "solid"|"gradient", colors: [...]}` from one shared definition that the
  web helper also reads.
- **Universal links:** Rails serves `/.well-known/apple-app-site-association` and
  `/.well-known/assetlinks.json`.

---

## 11. Delivery phases

| Phase | Scope | Exit criteria |
|---|---|---|
| **0 — Foundations** | §3: backups + restore drill, Solid Queue + Solid Cache in prod, worker process, Mission Control, CI fix. (Ruby 4.0.9 / Rails 8.1.4 is done.) | Recurring jobs firing in prod for a week |
| **1 — API skeleton + auth** | Base controller and concerns, Alba, rswag + OpenAPI CI check, `api_sessions`, login/refresh/logout/register/reset, `/config`, `/me`, rate limits | Same user logs in on web and mobile; `openapi.yaml` published to the mobile repo folder |
| **2 — Reads + CDN** | §4.2 extractions (web specs green), all read endpoints, ETags; §5 CDN routes and named variants | Every read matches the web page data for a test account; images served from `CDN_HOST` |
| **3 — Writes + uploads** | Direct uploads, profile + avatar, workouts (+ idempotency), clubs, events, timeline with images, support, devices, account deletion, moderation | Workout logged on mobile shows XP on web within seconds |
| **4 — Claims & locker** | XP claims, reward/cosmetic claim, equip | Concurrency specs prove no double claim; mobile and web give identical results |
| **5 — Strava + native push** | §8, §9, continuable Strava import | Connect, import and push work on both platforms in TestFlight / internal testing |
| **6 — Hardening & launch** | Load test on a production copy, connection budget check, rate-limit tuning, optional R2 move (§5), store submission | p95 < 300 ms on reads; DB connections within budget at peak |
| **7 — Cleanup** (later) | Mark web-push associations `deprecated: true`, then remove them if unused; retire Bucketeer if moved | ≥ 4 weeks after launch, after a backup |

**Data-safety checklist for every release that touches the database:**
- Fresh backup before deploy (the `release:` phase runs `db:migrate`).
- Migration rehearsed on a restored copy.
- Additive only, or the second step of an earlier expand/contract.
- Backfills are resumable (continuations), idempotent, and log what they changed.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| Moving logic out of web controllers (§4.2) changes web behaviour | Extract one section at a time; the existing request specs must stay green; no behaviour changes in the same PR |
| API traffic slows the web (same dynos and DB pool) | Connection budget (0.6), ETags, load test in Phase 6. If needed, run a second Heroku app from the same repo and DB for `/api` |
| Old app builds break on a response change | rswag/OpenAPI drift check in CI; additive changes only within `/v1`; `min_supported_version` + 426 |
| Double claims from retries or double taps | `Idempotency-Key`, plus the existing unique indexes and conditional updates; concurrency specs |
| Jobs lost or delayed (async adapter today) | Phase 0.2 before any API work; Mission Control alerts on failed jobs |
| Long jobs killed by daily dyno restarts | Active Job Continuations for Strava import, storage copy and season fan-out |
| Token theft | 15-min access tokens, rotating refresh with family revocation, secure storage on device, revoke-all on password change |
| Abuse of uploads | Purpose/type/size checks before presigning, per-user `rate_limit`, purge of unattached blobs |

---

## 13. Open decisions

1. **Storage provider:** stay on Bucketeer, or move to Cloudflare R2 through the mirror
   service (*recommended*, Phase 6).
2. **Re-authentication for `DELETE /api/v1/me`:** today a valid access token is enough.
   Asking for the password again would stop a stolen token from deleting an account.
3. **One Heroku app vs a separate API app** from the same repo: start with one
   (*recommended*); split only if Phase 6 load tests say so.
4. **Ruby 4.1:** upgrade after its stable release plus the first patch release; benchmark
   ZJIT then.
5. **A unique index on `club_memberships (club_id, user_id)`.** Joins are guarded by a
   row lock today. The index needs a cleanup of any duplicate rows already in
   production first, so it's a two-step release.

---

## 14. Before the first deploy

- **Processes:** the `Procfile` now has `worker: bin/jobs`. Scale it to one dyno on
  Heroku (or set `SOLID_QUEUE_IN_PUMA=1` on the web dyno instead).
- **Migrations:** `release: db:migrate` creates the Solid Queue, Solid Cache and API
  tables in the primary database. Take a backup first (§3 row 0.1).
- **Environment:**

  | Variable | Needed for |
  |---|---|
  | `CDN_HOST` | Image URLs on the CDN (unset: the app's own host) |
  | `MOBILE_MIN_SUPPORTED_VERSION` | Forcing old builds to update (unset: every build allowed) |
  | `STRAVA_MOBILE_REDIRECT_URI` | Strava connect from the app (unset: the web callback) |
  | `EXPO_ACCESS_TOKEN` | Expo push, if the Expo project requires it |
  | `IOS_APP_IDS`, `ANDROID_APP_PACKAGE`, `ANDROID_SHA256_CERT_FINGERPRINTS` | Universal links / app links (unset: 404) |
  | `PRIVACY_POLICY_URL`, `TERMS_URL` | Links returned by `GET /api/v1/config` |
  | `SLACK_WEBHOOK_URL_CONTENT_REPORTED` | Optional: a separate Slack channel for content reports |
  | `R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Only for the optional R2 move (§5) |

- **Behaviour changes on the web** that came with the shared code: manual workouts
  now need a sport and a duration; empty timeline posts and clubs without a name are
  refused; the timeline hides posts from blocked players; account deletion from the
  web profile works (it used to fail on foreign keys).
- **Known gap:** Rails' built-in validation messages ("can't be blank") have no
  Portuguese translation in this app, on the web or the API.

