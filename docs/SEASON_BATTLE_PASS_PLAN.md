# Season Battle Pass — Implementation Plan

> **Status: implemented.** All nine phases are built, migrated and covered by specs.
> See [§10 Build notes](#10-build-notes-what-shipped) for what changed against this plan.

Reference season: **Season 8 · Legacy of Champions** (1–31 August).
Goal: turn the current "season = a bag of challenges + 5 levels" model into a repeatable
**monthly battle pass** with dailies, weeklies, monthlies, elite/hidden content, missions,
an economy, a community goal, and multiple leaderboards — and be able to ship September
by writing one YAML file.

---

## 1. What already exists (and must be preserved)

The current season engine is architecturally sound. Its core pattern:

> **Durable completion ledger + idempotent recompute-from-scratch.**

| Piece | File | Role |
|---|---|---|
| `Season` | [season.rb](../app/models/season.rb) | Window, theme, `xp_multiplier`, status |
| `SeasonChallenge` | [season_challenge.rb](../app/models/season_challenge.rb) | Joins a `Challenge` into a season with `xp_reward` |
| `SeasonObjective` | [season_objective.rb](../app/models/season_objective.rb) | Non-workout goals (`join_club`, `club_workout`) |
| `SeasonParticipation` | [season_participation.rb](../app/models/season_participation.rb) | `xp`, `level`, `xp_breakdown` |
| `*_completions` | schema | **Durable ledger** — XP survives weekly resets |
| `SeasonProgressService` | [season_progress_service.rb](../app/services/season_progress_service.rb) | Recomputes XP from ledger + derived bonuses |
| `SeasonRewardGranter` | [season_reward_granter.rb](../app/services/season_reward_granter.rb) | Grants rewards ≤ level, idempotent via unique index |
| `RecomputeChallengeProgress` | [recompute_challenge_progress.rb](../app/services/recompute_challenge_progress.rb) | Workout → challenge progress → season ledger |
| `ChallengeEnroller` | [challenge_enroller.rb](../app/services/challenge_enroller.rb) | Auto-enroll + **back-fill existing workouts** |

**Every new mechanic below must follow the same pattern**: derive progress from workouts,
write a durable completion row, recompute XP from the ledger, grant rewards through a
unique index. Never increment a counter in place.

### Hard blockers in today's data model

| # | Blocker | Impact |
|---|---|---|
| 1 | `workouts.workout_date` is a **`date`** | "Run before 08:00", "after 23:00", "before 05:30" are **impossible** |
| 2 | No elevation / calories / elapsed-time columns | Elevation board, "no stopping", calorie dailies impossible |
| 3 | `Leveling::THRESHOLDS` = **5 levels**, global constant | Battle pass needs 30 levels, per-season |
| 4 | `Challenge` has **one** `target_value`/`target_unit` | Weeklies are compound ("15 km **AND** 4 workouts **AND** one run > 6 km") |
| 5 | `SeasonReward::REWARD_TYPES` = `title/badge/theme` only | No coins, cosmetics, XP boosts |
| 6 | No premium/free track concept | Premium pass unimplementable |
| 7 | `ResetWeeklyChallengesJob` wipes all `challenge_type: "weekly"` progress every Sunday | **Would destroy Week 1–4 named challenges** |
| 8 | `SeasonObjectives.progress` is a hardcoded `case` | Can't express 30+ challenge types |
| 9 | Only one leaderboard (XP) | Spec needs 6 |
| 10 | `Challenge::SPORTS = %w[run soccer]` but Strava importer maps `"bike"` | Pre-existing bug; bike workouts fail sport-scoped challenges |

---

## 2. Product decisions needed before coding

These change the work materially. My recommendation in **bold**.

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | **Premium pass monetization** | Real payments (Stripe/Pix) / admin-granted / free-for-all | **Model the `premium` flag + track gating now, grant via admin only. No payment flow in v1.** Payments are a separate epic. |
| D2 | **Cosmetics art** | Commission assets / CSS-only / defer | **Ship tier 1 as CSS-only** (name colors, gradient banners, ring frames, titles). Model trails/animations/outfits in the catalogue but render them as "owned, coming soon" cards. |
| D3 | **10,000,000 km community goal** | Literal / scaled to user base | **Scale it.** Set `target = participants × 60 km` at season start, or configure per season. 10M km is ~unreachable and kills the mechanic. |
| D4 | **"Walk 5,000 steps"** | Strava has no step data | **Drop it.** |
| D5 | **"Storm Runner" (run in rain)** | Weather API / self-declared / drop | **Self-declared checkbox on the workout**, or drop. A weather API per workout is a whole integration. |
| D6 | **"Run with a friend"** | Strava doesn't expose it reliably | **Reframe as "post a workout to a club timeline"** — data you already have. |
| D7 | **"Run on a new route"** | Hash `map.summary_polyline` | Feasible but noisy (GPS drift). **Defer to Phase 6.** |
| D8 | **Day boundary timezone** | UTC / per-user / season-fixed | **Season-fixed `America/Sao_Paulo`.** Add `seasons.time_zone`. Critical for dailies and hour-based challenges. |
| D9 | **Elite challenges retroactive?** | Progress only after L20 / retroactive on unlock | **Retroactive.** Progress accrues silently; completion records the moment L20 is reached. Simpler and kinder. |
| D10 | **Mid-month launch** (today is 11 Aug) | Backfill / start clean | **Backfill everything except dailies.** `ChallengeEnroller` + `SeasonProgressService` already recompute from scratch; dailies start on import day. |

---

## 3. Architecture: the one thing that makes this tractable

Everything in the spec — dailies, weeklies, monthlies, elites, hidden, legacy missions,
leaderboards, community goals — is the same question:

> *"Given a user, a time window, and some options, what is the numeric value of metric X?"*

So build **one metric registry** and let every mechanic consume it.

```ruby
# app/services/challenge_metrics.rb
module ChallengeMetrics
  # Each metric: .call(user:, window:, options: {}) => Numeric
  #              .unit                              => "km" | "count" | "seconds" | ...
  #              .comparator                        => :gte (default) | :lte
  REGISTRY = {
    "distance_km"            => Metrics::DistanceKm,
    "activity_count"         => Metrics::ActivityCount,
    "active_days"            => Metrics::ActiveDays,
    "longest_activity_km"    => Metrics::LongestActivityKm,
    "activities_over_km"     => Metrics::ActivitiesOverKm,      # options: { km: 10 }
    "consecutive_days"       => Metrics::ConsecutiveDays,
    "weeks_with_activity"    => Metrics::WeeksWithActivity,
    "elevation_gain_m"       => Metrics::ElevationGain,
    "calories"               => Metrics::Calories,
    "start_before_hour"      => Metrics::StartBeforeHour,       # options: { hour: 8 }
    "start_after_hour"       => Metrics::StartAfterHour,        # options: { hour: 23 }
    "beat_previous_day"      => Metrics::BeatPreviousDay,
    "personal_record"        => Metrics::PersonalRecord,        # options: { kind: "distance" }
    "fastest_5k_seconds"     => Metrics::Fastest5k,             # comparator :lte
    "uninterrupted_activity" => Metrics::Uninterrupted,         # elapsed ≈ moving time
    "club_member"            => Metrics::ClubMember,            # replaces SeasonObjectives case
    "club_workout_count"     => Metrics::ClubWorkoutCount,
    "battle_pass_level"      => Metrics::BattlePassLevel,
    "new_route"              => Metrics::NewRoute               # Phase 6
  }.freeze

  def self.call(key, user:, window:, options: {})
    REGISTRY.fetch(key).call(user: user, window: window, options: options.symbolize_keys)
  end
end
```

Each metric is ~10 lines, individually unit-testable, and reused by every mechanic.
**This registry is the highest-value thing to build first and the thing to test hardest.**

---

## 4. Phased plan

Each phase is independently shippable and leaves the app working.

---

### Phase 0 — Workout data foundation ⚠️ blocks everything

**Migration** `AddActivityDetailsToWorkouts`:

```ruby
add_column :workouts, :started_at_local,     :datetime   # from Strava start_date_local
add_column :workouts, :started_at,           :datetime   # UTC
add_column :workouts, :start_time_known,     :boolean, default: false, null: false
add_column :workouts, :elevation_gain_m,     :decimal, precision: 8, scale: 1
add_column :workouts, :calories,             :integer
add_column :workouts, :moving_time_seconds,  :integer
add_column :workouts, :elapsed_time_seconds, :integer
add_column :workouts, :route_signature,      :string     # Digest of map.summary_polyline
add_index  :workouts, [:user_id, :started_at_local]
```

`start_time_known` matters: without it, manually-logged workouts (which have no time)
would silently satisfy "run before 05:30". Hour-based metrics **must** filter
`where(start_time_known: true)`.

**Tasks**
1. Migration above.
2. `Strava::ActivityImporter#upsert` — map `start_date_local`, `start_date`,
   `total_elevation_gain`, `calories`, `moving_time`, `elapsed_time`, `map.summary_polyline`.
   Set `start_time_known: true`.
3. `rake seasons:backfill_workout_details` — re-read `raw_data` for existing Strava rows
   (the full activity hash is already stored, so no re-fetch needed). Manual rows get
   `started_at_local = workout_date.midday`, `start_time_known: false`.
4. Manual workout form: optional start-time field.
5. Fix `Challenge::SPORTS` — add `"bike"` (blocker #10).

**Tests**: importer maps every new field; backfill task is idempotent; manual workouts
never satisfy hour metrics.

---

### Phase 1 — 30-level battle pass + reward tracks

**Migrations**

```ruby
# seasons
add_column :seasons, :level_curve, :jsonb, default: [], null: false  # cumulative XP floors
add_column :seasons, :max_level,   :integer, default: 5,  null: false
add_column :seasons, :time_zone,   :string,  default: "America/Sao_Paulo", null: false
add_column :seasons, :slogan,      :string

# season_rewards
add_column :season_rewards, :track,        :string,  default: "free", null: false  # free | premium
add_column :season_rewards, :coins,        :integer, default: 0,      null: false
add_column :season_rewards, :unlock_kind,  :string,  default: "level", null: false # level | legacy | completion_tier | community
add_column :season_rewards, :unlock_value, :integer                                # threshold for non-level unlocks
add_column :season_rewards, :position,     :integer, default: 0,      null: false
add_column :season_rewards, :payload,      :jsonb,   default: {},     null: false
change_column_null :season_rewards, :level, true                                    # non-level rewards have no level

# season_participations — denormalised stats, recomputed each recalc (powers leaderboards + season page)
add_column :season_participations, :premium,             :boolean, default: false, null: false
add_column :season_participations, :premium_granted_at,  :datetime
add_column :season_participations, :total_distance_km,   :decimal, precision: 10, scale: 2, default: 0, null: false
add_column :season_participations, :activities_count,    :integer, default: 0, null: false
add_column :season_participations, :elevation_gain_m,    :decimal, precision: 10, scale: 1, default: 0, null: false
add_column :season_participations, :longest_streak_days, :integer, default: 0, null: false
add_column :season_participations, :best_5k_seconds,     :integer
add_column :season_participations, :completion_percent,  :integer, default: 0, null: false
add_column :season_participations, :medal_fragments,     :integer, default: 0, null: false
```

**Level curve.** Replace the global `Leveling` module with a per-season value object:

```ruby
# app/models/seasons/level_curve.rb
class Seasons::LevelCurve
  def self.for(season)
    new(season.level_curve.presence || Leveling::THRESHOLDS)
  end
  # level_for(xp), floor_for(level), next_floor(xp), progress_percent(xp), max_level
end
```

`Leveling` stays as the default curve so existing seasons keep working. Update the
5 call sites: [season_progress_service.rb:36](../app/services/season_progress_service.rb#L36),
[seasons/show.html.erb:33-34](../app/views/seasons/show.html.erb#L33-L34),
[challenges/index.html.erb:31](../app/views/challenges/index.html.erb#L31),
[admin/seasons/show.html.erb:82](../app/views/admin/seasons/show.html.erb#L82).

**Proposed 30-level curve**: `floor(n) = 300·(n−1) + 10·(n−1)²`

| Level | XP floor | | Level | XP floor |
|---|---|---|---|---|
| 1 | 0 | | 20 (elite unlock) | **9,310** |
| 5 | 1,360 | | 25 | 12,960 |
| 10 | 3,510 | | 30 (max) | **17,110** |

**XP budget check** (tune this with a `rake seasons:simulate` task before launch):

| Source | Max | Realistic (engaged, non-completionist) |
|---|---|---|
| Workouts (20 XP × 25) | 500 | 400 |
| Streak + consistency + club | 200 | 150 |
| Dailies (3/day × 31 × 50 XP) | 4,650 | 2,800 (60%) |
| Weeklies (4 × 1,000) | 4,000 | 3,000 |
| Monthlies (4 × 750) | 3,000 | 1,500 |
| Legacy missions (5 × 400 + 1,000) | 3,000 | 2,400 |
| Elite (5 × 1,000) | 5,000 | 0 |
| **Total** | **~20,350** | **~10,250 → level ~21** |

Design intent: **level 30 must be reachable without Elite challenges** (Elite unlocks at
20 and has its own reward). Currently a completionist without Elite hits ~15,350 → level 28.
Nudge weekly/monthly XP up ~15% or lower the L30 floor to ~15,000.

**Track gating** in `SeasonRewardGranter#grant_up_to`:

```ruby
@season.season_rewards
       .where(unlock_kind: "level", level: ..level)
       .where(track: @participation.premium? ? %w[free premium] : %w[free])
```

Also split `grant_up_to` into `grant_for_level` / `grant_for_unlock(kind, value)` so
legacy missions, completion tiers, and community milestones reuse the same idempotent path.

---

### Phase 2 — Multi-requirement challenge engine

This is the heart of the work.

**Migrations**

```ruby
create_table :challenge_requirements do |t|
  t.references :challenge, null: false, foreign_key: true
  t.integer :position,   default: 0, null: false
  t.string  :metric,     null: false           # ChallengeMetrics key
  t.string  :comparator, default: "gte", null: false
  t.decimal :target,     precision: 12, scale: 2, null: false
  t.string  :unit
  t.jsonb   :options,    default: {}, null: false
  t.string  :label_key                          # i18n key for display
  t.timestamps
end

add_column :challenge_participations, :requirement_progress, :jsonb, default: {}, null: false

# season_challenges
add_column :season_challenges, :category,        :string,  default: "standard", null: false
                                # daily | weekly | monthly | elite | hidden | standard
add_column :season_challenges, :unlock_level,    :integer, default: 0, null: false
add_column :season_challenges, :hidden,          :boolean, default: false, null: false
add_column :season_challenges, :coin_reward,     :integer, default: 0, null: false
add_column :season_challenges, :fragment_reward, :integer, default: 0, null: false
add_column :season_challenges, :week_index,      :integer               # 1..4 for weeklies
```

**Backfill**: create one `challenge_requirement` per existing challenge from its
`target_unit`/`target_value` (`km → distance_km`, `times → activity_count`, `hours → duration_hours`).
Keep the legacy columns for display and for the admin form.

**`RecomputeChallengeProgress` rewrite** (keep the class, extend the logic):

```ruby
def call
  progress = @challenge.challenge_requirements.index_with do |req|
    ChallengeMetrics.call(req.metric, user: @user, window: window, options: req.options)
  end
  @participation.update!(
    requirement_progress: progress.transform_keys { |r| r.id.to_s },
    progress_value: headline_progress(progress)   # first requirement, for existing UI
  )
  award_completion if all_requirements_met?(progress) && @participation.completed_at.nil?
  @participation
end
```

`all_requirements_met?` respects each requirement's `comparator` (`:lte` for fastest-5k style).

**Windows.** Extend `Challenge#workout_window` to return a **time range** when any
requirement is hour-sensitive, using `season.time_zone`. For the season's Week 1–4
challenges use `challenge_type: "custom"` with explicit `starts_at`/`ends_at` —
**never `"weekly"`**, or `ResetWeeklyChallengesJob` will wipe them every Sunday (blocker #7).
Add a guard comment there, and consider narrowing that job to challenges with no
`season_challenges` row.

**Elite gating**: in `record_season_completions`, skip `season_challenge` rows where
`unlock_level > participation.level`. Because everything recomputes from scratch, progress
accrues silently and completion lands automatically on reaching L20 (decision D9).

**Hidden challenges**: `hidden: true` → excluded from the season page challenge list until
a completion row exists, then rendered in a "Secrets discovered" section.

---

### Phase 3 — Daily challenges

**Migrations**

```ruby
create_table :daily_challenge_templates do |t|
  t.string  :key,     null: false, index: { unique: true }
  t.string  :metric,  null: false
  t.decimal :target,  precision: 12, scale: 2, null: false
  t.jsonb   :options, default: {}, null: false
  t.integer :xp_reward,   default: 50, null: false
  t.integer :coin_reward, default: 25, null: false
  t.integer :weight,      default: 1,  null: false   # selection weighting
  t.boolean :active,      default: true, null: false
  t.boolean :requires_start_time, default: false, null: false
  t.timestamps
end

create_table :daily_challenge_assignments do |t|
  t.references :user, null: false, foreign_key: true
  t.references :season, null: false, foreign_key: true
  t.references :daily_challenge_template, null: false, foreign_key: true
  t.date     :challenge_date, null: false
  t.datetime :completed_at
  t.integer  :xp_awarded,   default: 0, null: false
  t.integer  :coin_awarded, default: 0, null: false
  t.timestamps
  t.index [:user_id, :challenge_date, :daily_challenge_template_id],
          unique: true, name: "idx_daily_assignments_unique"
  t.index [:season_id, :challenge_date]
end
```

**`DailyChallengeAssigner`** — deterministic, so the same user always gets the same 3 for
a given date even if the job runs twice:

```ruby
seed = Digest::MD5.hexdigest("#{user.id}-#{date}-#{season.id}").to_i(16)
templates = eligible_templates(user).sample(3, random: Random.new(seed))
```

Filter out `requires_start_time` templates for users whose workouts never carry a time
(otherwise they get unwinnable dailies).

**`AssignDailyChallengesJob`** — recurring at `00:05 America/Sao_Paulo`, iterates active
season participants. Also called lazily on season-page visit so a user who joins mid-day
sees today's set immediately.

**Evaluation** — inside `SeasonProgressService#recalculate`, evaluate today's **and
yesterday's** assignments (grace window for late Strava imports). Window = that single day
in `season.time_zone`. XP folds into `xp_breakdown[:dailies]`.

**Add to `config/recurring.yml`**:
```yaml
assign_daily_challenges:
  class: AssignDailyChallengesJob
  schedule: every day at 12:05am
aggregate_community_goals:
  class: AggregateCommunityGoalsJob
  schedule: every 15 minutes
```

⚠️ **"Perfect Month"** only counts days from the user's join date — a user who joined on
the 11th has no assignments for days 1–10. Document this in the challenge description.

---

### Phase 4 — Economy & cosmetics

**Migrations**

```ruby
add_column :users, :coins, :integer, default: 0, null: false
add_column :users, :equipped_cosmetics, :jsonb, default: {}, null: false

create_table :coin_transactions do |t|
  t.references :user, null: false, foreign_key: true
  t.integer :amount, null: false                 # signed
  t.string  :reason, null: false                 # "season_reward", "daily_challenge", ...
  t.string  :reason_key, null: false             # idempotency key, e.g. "season_reward:42"
  t.jsonb   :metadata, default: {}, null: false
  t.timestamps
  t.index [:user_id, :reason_key], unique: true  # ← the idempotency gate
end

create_table :cosmetics do |t|
  t.string  :key,  null: false, index: { unique: true }
  t.string  :kind, null: false   # banner|avatar|frame|trail|name_color|effect|emoji_pack|outfit|border
  t.string  :name
  t.string  :rarity, default: "common", null: false
  t.string  :css_class
  t.boolean :animated, default: false, null: false
  t.boolean :renderable, default: true, null: false  # false = owned but not yet displayable
  t.timestamps
end

create_table :user_cosmetics do |t|
  t.references :user, null: false, foreign_key: true
  t.references :cosmetic, null: false, foreign_key: true
  t.string   :source
  t.datetime :unlocked_at, null: false
  t.timestamps
  t.index [:user_id, :cosmetic_id], unique: true
end

create_table :user_xp_boosts do |t|
  t.references :user, null: false, foreign_key: true
  t.decimal  :multiplier, precision: 4, scale: 2, default: 2.0, null: false
  t.datetime :starts_at, null: false
  t.datetime :ends_at,   null: false
  t.string   :source_key, null: false
  t.timestamps
  t.index [:user_id, :source_key], unique: true
end
```

`SeasonReward::REWARD_TYPES` becomes `%w[title badge theme coins cosmetic xp_boost]`, and
`SeasonRewardGranter#apply` gains the three new branches.

⚠️ **XP boost + recompute-from-scratch interact badly.** Because `SeasonProgressService`
recalculates total XP every time, a boost cannot be a global multiplier — it must be applied
**per workout, by that workout's date**:

```ruby
def workouts_xp
  season_workouts.sum { |w| (WORKOUT_XP * boost_multiplier_on(w.workout_date)).round }
end
```

**Cosmetic rendering (tier 1, CSS-only)**: `name_color`, `frame` (ring around avatar),
`banner` (gradient header on profile), `border`, `title` (already supported). Everything
else gets `renderable: false` and shows in a new **Collection** page as owned-but-pending.

---

### Phase 5 — Legacy missions, medals, end-of-season

**Legacy missions.** Extend `season_objectives` rather than adding a new model:

```ruby
add_column :season_objectives, :track,   :string, default: "standard", null: false  # standard | legacy
add_column :season_objectives, :metric,  :string
add_column :season_objectives, :options, :jsonb, default: {}, null: false
add_column :season_objectives, :icon,    :string
```

Refactor `SeasonObjectives.progress` ([season_objectives.rb](../app/services/season_objectives.rb))
to delegate to `ChallengeMetrics`, keeping `join_club`/`club_workout` as registry entries
(`club_member`, `club_workout_count`). The hardcoded `case` disappears.

The five missions map cleanly:

| Mission | Metric | Target |
|---|---|---|
| Discipline | `activity_count` | 10 |
| Courage | `personal_record` (`kind: "distance"`) | 1 |
| Resilience | `consecutive_days` | 7 |
| Strength | `distance_km` | 80 |
| Legacy | `battle_pass_level` | 30 |

Completing all five → `SeasonReward` with `unlock_kind: "legacy"`, granted by
`SeasonRewardGranter#grant_for_unlock(:legacy, 5)` from within the recalc.

**Champion Medals.** `season_challenges.fragment_reward` and `season_objectives.fragment_reward`
feed `season_participations.medal_fragments`, recomputed from the ledger each recalc.
Bronze/Silver/Gold/Diamond are `season_rewards` with `unlock_kind: "medal_fragments"`.

**End-of-season.** `completion_percent` = weighted completed content ÷ total content,
recomputed each recalc. New `SeasonFinalizeJob`, triggered when `status` flips to `ended`
(add an `after_update_commit` on `Season`):

- 25/50/75/100% → `season_rewards` with `unlock_kind: "completion_tier"`
- 100% additionally grants the permanent title `august_legend_2026` and the exclusive border
- Writes a `SeasonActivity`, sends a push, idempotent via `season_reward_grants`

---

### Phase 6 — Community event & leaderboards

**Community goal**

```ruby
create_table :season_community_goals do |t|
  t.references :season, null: false, foreign_key: true
  t.string  :key, null: false
  t.string  :metric, null: false
  t.decimal :target_value,  precision: 14, scale: 2, null: false
  t.decimal :current_value, precision: 14, scale: 2, default: 0, null: false
  t.datetime :computed_at
  t.timestamps
  t.index [:season_id, :key], unique: true
end

create_table :season_community_milestones do |t|
  t.references :season_community_goal, null: false, foreign_key: true
  t.decimal :threshold, precision: 14, scale: 2, null: false
  t.references :season_reward, foreign_key: true
  t.datetime :reached_at
  t.timestamps
end
```

`AggregateCommunityGoalsJob` (every 15 min): one aggregate query per goal across the season
window → update `current_value` → for milestones newly crossed, stamp `reached_at` and
enqueue `GrantCommunityMilestoneJob` in batches of 500 participants. `reached_at` is the
idempotency gate; grants are additionally protected by `season_reward_grants`.

Remember **decision D3** — set the target relative to community size.

**Leaderboards.** `SeasonLeaderboard.new(season, board:).top(limit)`, 6 boards:

| Board | Source |
|---|---|
| XP | `season_participations.xp` |
| Distance | `season_participations.total_distance_km` |
| Activities | `season_participations.activities_count` |
| Longest streak | `season_participations.longest_streak_days` |
| Fastest 5 km | `season_participations.best_5k_seconds` (ASC, nulls last) |
| Most elevation | `season_participations.elevation_gain_m` |

All six read the **denormalised columns added in Phase 1**, populated during
`SeasonProgressService#recalculate`. No per-request aggregation over `workouts`.
Cache each board for 5 minutes.

---

### Phase 7 — UI

**`seasons/show`** ([current view](../app/views/seasons/show.html.erb)) becomes section-based:

1. **Header** — theme gradient, slogan, dates, premium badge, import-workouts CTA (already added)
2. **Battle Pass track** — horizontally scrollable strip of 30 nodes, two rows (free / premium),
   current level marker, locked/unlocked/claimed states
3. **Today** — the 3 daily challenges with progress rings
4. **Challenges** — tabs: Weekly (4 named weeks) · Monthly · Elite (locked until L20, shown
   greyed with "Unlocks at level 20") · Secrets (only discovered ones)
5. **Legacy Missions** — 5-node path with the 5 values
6. **Community goal** — a big progress bar with milestone pips
7. **Leaderboards** — board switcher, top 10 + "your position"
8. **Collection** — medals, fragments, cosmetics owned

**Theme.** `Season::THEMES` gains `"legacy"` (dark blue / gold / silver / frost), and
`seasons_helper.season_theme_classes` gains the matching gradient.

**Admin.** Blueprint import button; category/`unlock_level`/`track`/coin fields on the
season-challenge and reward forms; premium toggle on a participation; community goal editor.
Note `admin/seasons/show.html.erb:82` hardcodes `max: Leveling::MAX_LEVEL` — switch to the
season's curve.

**i18n.** Every string in **both** `en.yml` and `pt.yml`. pt-BR is the primary audience —
write pt first, en second. Add a `challenges.defaults.*` entry per seeded challenge key
(the existing convention in [en.yml:68](../config/locales/en.yml#L68)).

---

### Phase 8 — Season blueprint (what makes this repeatable)

The payoff. One YAML file per season, imported idempotently.

`db/seeds/seasons/season_8_legacy_of_champions.yml`:

```yaml
key: season_8_legacy_of_champions
name: "Legacy of Champions"
slogan: "Every kilometer tells a story. Build your legacy."
theme: legacy
time_zone: America/Sao_Paulo
starts_at: 2026-08-01
ends_at: 2026-08-31
max_level: 30
level_curve_formula: "300*(n-1) + 10*(n-1)**2"

challenges:
  - key: s8_week1_beginning
    category: weekly
    week_index: 1
    challenge_type: custom
    starts_at: 2026-08-01
    ends_at: 2026-08-07
    xp_reward: 1000
    fragment_reward: 10
    requirements:
      - { metric: distance_km,         target: 15 }
      - { metric: activity_count,      target: 4 }
      - { metric: longest_activity_km, target: 6 }

  - key: s8_month_mountain
    category: monthly
    challenge_type: custom
    xp_reward: 750
    requirements:
      - { metric: distance_km, target: 100 }

  - key: s8_elite_150
    category: elite
    unlock_level: 20
    xp_reward: 1000
    requirements:
      - { metric: distance_km, target: 150 }

  - key: s8_hidden_early_bird
    category: hidden
    hidden: true
    xp_reward: 300
    requirements:
      - { metric: start_before_hour, target: 1, options: { hour: 5, minute: 30 } }

rewards:
  - { level: 1,  track: free,    reward_type: badge,    reward_key: august_badge }
  - { level: 3,  track: free,    reward_type: coins,    coins: 500 }
  - { level: 30, track: free,    reward_type: title,    reward_key: champion }
  - { level: 30, track: premium, reward_type: cosmetic, reward_key: legend_of_august_outfit }
  - { unlock_kind: legacy,          unlock_value: 5,   reward_type: cosmetic, reward_key: golden_footsteps }
  - { unlock_kind: completion_tier, unlock_value: 100, reward_type: title,    reward_key: august_legend_2026 }

legacy_missions:
  - { key: discipline, metric: activity_count,    target: 10, xp_reward: 400 }
  - { key: courage,    metric: personal_record,   target: 1,  xp_reward: 400 }
  - { key: resilience, metric: consecutive_days,  target: 7,  xp_reward: 400 }
  - { key: strength,   metric: distance_km,       target: 80, xp_reward: 400 }
  - { key: legacy,     metric: battle_pass_level, target: 30, xp_reward: 400 }

community_goal:
  key: august_marathon
  metric: distance_km
  target_mode: per_participant     # target = participants × per_participant_km
  per_participant_km: 60
  milestones: [20, 40, 60, 80, 100]   # percent

daily_templates:
  - { key: run_3km,        metric: distance_km,       target: 3 }
  - { key: one_activity,   metric: activity_count,    target: 1 }
  - { key: before_8am,     metric: start_before_hour, target: 1, options: { hour: 8 },  requires_start_time: true }
  - { key: after_6pm,      metric: start_after_hour,  target: 1, options: { hour: 18 }, requires_start_time: true }
  - { key: beat_yesterday, metric: beat_previous_day, target: 1 }
  - { key: burn_300kcal,   metric: calories,          target: 300 }
  - { key: no_stopping,    metric: uninterrupted_activity, target: 1 }
```

`Seasons::BlueprintImporter` — upsert by `key` at every level, never destructive.
Rake task: `rails seasons:import[season_8_legacy_of_champions]`.

**Full content mapping** for the reference season:

| Content | Metric(s) | Target |
|---|---|---|
| **W1 The Beginning** | distance_km / activity_count / longest_activity_km | 15 / 4 / 6 |
| **W2 Momentum** | distance_km / consecutive_days / personal_record | 20 / 3 / 1 |
| **W3 Endurance** | distance_km / activities_over_km(10) / activity_count | 25 / 1 / 5 |
| **W4 The Champion** | distance_km / activities_over_km(10) / activity_count | 30 / 2 / 7 |
| **The Mountain** | distance_km | 100 |
| **The Warrior** | activity_count | 25 |
| **The Collector** | completed weekly challenges | 4 |
| **The Unstoppable** | weeks_with_activity | 5 |
| **Elite** | distance_km / consecutive_days / longest_activity_km / activities_over_km(10) / elevation_gain_m | 150 / 20 / 21.1 / 3 / *see note* |
| 🥶 Early Bird | start_before_hour(5:30) | 1 |
| 🌙 Night Owl | start_after_hour(23) | 1 |
| 🔥 Fire Within | consecutive_days | 7 |
| 💯 Perfect Month | all dailies since join | — |
| 🌧 Storm Runner | — | **see D5** |

*Note: "50,000 elevation meters" is not physically plausible in a month (Everest is 8,848 m
of gain; 50,000 m is ~6 Everests). Suggest **5,000 m**.*

---

## 5. Performance: the one real scaling risk

`Workout#credit_season_progress` enqueues a `SeasonRecalcJob` **per workout, per active
season**. A Strava bulk import of 40 activities fires 40 recalcs, and after Phase 2 each
recalc evaluates every requirement of every season challenge plus dailies plus missions.

Mitigations, in order of value:

1. **Debounce.** Make `SeasonRecalcJob` a unique job (drop if one is already queued for the
   same `user_id`/`season_id`), or enqueue with a short delay so an import collapses into one run.
2. **Scope the recompute.** `Strava::ActivityImporter` already recomputes challenges in a
   loop *and* every workout triggers its own recalc — deduplicate: import all workouts, then
   recompute once.
3. **Skip out-of-window challenges.** Only recompute challenges whose window contains at
   least one of the newly-imported workout dates.
4. **Batch the metric queries.** Load the season's workouts once per recalc and let metrics
   operate on the in-memory collection instead of issuing one query each (~20 metrics ×
   ~20 challenges = 400 queries otherwise). **Do this in Phase 2, not later** — it is a
   design constraint on the metric interface:
   `.call(workouts:, user:, window:, options:)` where `workouts` is a preloaded array.

Also add `PushNotifier` throttling — `Workout#notify_workout_xp` already uses a collapsing
`tag`, but 40 pushes on import is still 40 sends.

---

## 6. Testing strategy

Existing suite: RSpec, `spec/{models,services,jobs,requests}`.

| Priority | What | Why |
|---|---|---|
| **P0** | One spec per `ChallengeMetrics` entry | Everything else is built on them; cheap and high-yield |
| **P0** | `RecomputeChallengeProgress` — multi-requirement completion, partial progress, `:lte` comparator | Core correctness |
| **P0** | `SeasonRewardGranter` — track gating, idempotency under concurrent recalc | Double-granting rewards is user-visible and unfixable |
| **P1** | `SeasonProgressService` — `xp_breakdown` sums, XP boost by date, level-up transitions | XP regressions are trust-destroying |
| **P1** | `DailyChallengeAssigner` — determinism, no duplicates, `requires_start_time` filtering | |
| **P1** | `Seasons::BlueprintImporter` — run twice, assert no duplicates and no data loss | This is the repeatability guarantee |
| **P2** | `AggregateCommunityGoalsJob` — milestone crossing granted exactly once | |
| **P2** | Request specs for the new season page sections | |

Extend the existing [reset_weekly_challenges_job_spec.rb](../spec/jobs/reset_weekly_challenges_job_spec.rb)
with a case proving season-attached weekly challenges are **not** reset (blocker #7).

---

## 7. Suggested sequencing

| Order | Phase | Ships | Depends on |
|---|---|---|---|
| 1 | **0 — Workout data** | Nothing user-visible; unblocks all | — |
| 2 | **1 — 30 levels + tracks** | Battle pass bar goes to 30 | 0 |
| 3 | **2 — Requirement engine** | Compound weeklies/monthlies/elite/hidden | 0, 1 |
| 4 | **8 — Blueprint (partial)** | August season live with weekly/monthly/elite | 2 |
| 5 | **3 — Dailies** | Daily loop, the biggest retention lever | 2 |
| 6 | **5 — Missions + medals + finale** | Long-term goals, end-of-season payoff | 2, 3 |
| 7 | **4 — Economy + cosmetics** | Coins and CSS cosmetics | 1 |
| 8 | **6 — Community + leaderboards** | Social layer | 1, 2 |
| 9 | **7 — UI polish** | Continuous, per phase | all |

**Minimum viable August** = phases 0 → 1 → 2 → 8. That gives a real 30-level battle pass
with the four named weeks, four monthlies, elite gating, and hidden challenges — without
coins, cosmetics, dailies, or the community event. Everything after is additive.

---

## 8. Migration inventory

| Phase | Migration | Tables touched |
|---|---|---|
| 0 | `AddActivityDetailsToWorkouts` | workouts |
| 1 | `AddBattlePassToSeasons` | seasons |
| 1 | `AddTracksToSeasonRewards` | season_rewards |
| 1 | `AddStatsToSeasonParticipations` | season_participations |
| 2 | `CreateChallengeRequirements` | challenge_requirements (+ backfill) |
| 2 | `AddProgressToChallengeParticipations` | challenge_participations |
| 2 | `AddCategoryToSeasonChallenges` | season_challenges |
| 3 | `CreateDailyChallenges` | daily_challenge_templates, daily_challenge_assignments |
| 4 | `CreateEconomy` | users, coin_transactions |
| 4 | `CreateCosmetics` | cosmetics, user_cosmetics, user_xp_boosts |
| 5 | `AddLegacyTrackToSeasonObjectives` | season_objectives |
| 6 | `CreateCommunityGoals` | season_community_goals, season_community_milestones |

---

## 9. Open questions to answer before Phase 2

1. **D1** — is premium ever going to be paid, or is it a loyalty/invite reward? Changes whether
   `premium` needs an audit trail.
2. **D3** — what is the realistic active-user count in August? Sets the community target.
3. **D8** — confirm `America/Sao_Paulo` as the single day boundary (vs. per-user timezone).
4. Does Strava's scope currently return `calories`? It requires the activity detail endpoint
   on some plans — verify against a real payload before writing calorie dailies.
5. Should Elite challenges be visible-but-locked at level < 20, or completely hidden?
   (Visible-but-locked is the stronger motivator.)

---

## 10. Build notes: what shipped

All nine phases are implemented. This section records where the build **differed
from the plan above**, and why — the plan text is left intact as the design record.

### Verified end to end

A simulated August (10 runs, one at 05:20, 7-day streak) exercised on real dev data:

| Result | Value |
|---|---|
| Recalculation time | **130 ms** across 19 challenges with compound requirements |
| Compound weekly | Week 1 completed on 15 km **+** 4 workouts **+** 6 km run |
| Secrets fired | Early Bird, Fire Within, Trailblazer, Unbroken |
| Legacy missions | Discipline, Resilience recorded with fragments |
| Rewards | L1/L3/L5/L8 free track only; premium withheld until `grant_premium!` |
| Medals | 50 fragments → bronze tier |
| Community goal | 69/120 km = 57%, milestones 20% and 40% paid out |
| Leaderboards | All six populate from denormalised columns |

`rails 'seasons:simulate[season_8_legacy_of_champions]'` reports the tuned curve:
completionist **level 30**, engaged player **level 22**, and **level 30 is reachable
without elite content** — the design intent from §4 Phase 1.

### Changes from the plan

1. **`start_minute_of_day` added to workouts** (not in the original migration).
   Strava serialises `start_date_local` as a wall clock with a bogus `Z` suffix, so
   *any* timezone conversion on the datetime shifts it. An integer computed once at
   write time is immune, and makes hour-based metrics trivially indexable.

2. **`Wallet` uses `increment!`**, not a hand-rolled `update_all` +
   `clear_attribute_change` (which is private API). Same atomic SQL, public interface.

3. **`season_activities.user_id` is now nullable.** Community milestones belong to
   the whole season; attributing them to an arbitrary participant would misreport
   who did what.

4. **`SeasonRecalcJob.enqueue_debounced`** collapses a burst into two runs per
   20-second window — one immediate so the UI updates, one trailing to catch what
   landed during the first. `Strava::ActivityImporter#import_many` recomputes once
   per batch instead of once per activity.

5. **Metrics take a preloaded `ChallengeMetrics::Context`**, as §5 required. One
   workout history is read per recalculation and shared across every challenge,
   objective and daily.

6. **Completion percent excludes hidden challenges** from the denominator. A player
   cannot aim at a secret they have not been told exists, so counting them would
   make 100% unreachable by design.

7. **`ResetWeeklyChallengesJob` now scopes to `where.missing(:season_challenges)`.**
   Blueprint challenges are already `custom`; this is the second line of defence
   against blocker #7, and it is covered by a dedicated spec.

### Pre-existing issues found and fixed

- **`.env` pointed every environment at the development database.** Rails applies
  `DATABASE_URL` globally, so `RAILS_ENV=test` connected to
  `sports_communities_development` — the suite had been running against dev data,
  and `db:test:prepare` was only prevented from wiping it by Rails' environment
  guard. Fixed with `.env.test` (dotenv loads it with higher precedence in test).
  **This is worth knowing about beyond this work.**
- `Challenge::SPORTS` lacked `"bike"` while the Strava importer produced it, so
  bike workouts could never match a sport-scoped challenge.
- `spec/services/strava/activity_importer_spec.rb` asserted progress using a
  hardcoded May 2026 activity date against a current-week window — it rotted with
  the calendar. Now window-relative.
- `spec/jobs/reset_weekly_challenges_job_spec.rb` set `status: "archived"`, which
  is not a `Challenge::STATUSES` value, so the update never saved.

### Known-failing, left alone

`spec/requests/home_spec.rb` (4 examples) asserts translation keys
(`home.hero.headline_lead`, `home.features.*`) that the redesigned landing page no
longer uses. These fail on `main` too and belong to a different subsystem —
fixing them means deciding what the specs *should* assert about the new page.

### Decisions applied

D1 premium modelled but admin-granted (no payments) · D2 CSS-only cosmetics, the
rest collectible via `renderable: false` · D3 community goal scaled to
`participants × 60 km` · D4 steps dropped · D5 rain dropped · D6 "with a friend" →
`timeline_posts` · D7 `new_route` shipped (route-signature hashing was cheap once
polylines were stored) · D8 `America/Sao_Paulo` per season · D9 elite retroactive ·
D10 backfill everything except dailies.

### Still open

- **Calories from Strava** — present in the dev payloads inspected, but confirm the
  detail endpoint returns it for all accounts before relying on the calorie daily.
- **`Rails.cache` is MemoryStore in development**, which is per-process. The recalc
  debounce needs a shared store (Solid Cache / Redis) to collapse bursts across
  multiple production workers.
- **Cosmetic art** for the 8 `renderable: false` items (trails, effects, outfit,
  avatar, emoji pack).

---

## 11. Configurable levels and escalating community goals

Two changes after the first build.

### Level count is now a season setting

Previously the level count was effectively fixed: the stored `level_curve`'s own
length defined it, so editing `max_level` in the admin form silently did nothing.

The curve is now **derived** from two independent settings, and rebuilt on save
whenever either moves:

| Setting | Means | Default |
|---|---|---|
| `seasons.max_level` | How many levels (1–100) — **pacing** | 5 |
| `seasons.top_level_xp` | What the top level costs — **difficulty** | 17,110 |
| `seasons.curve_exponent` | Curve steepness; >1 front-loads early levels | 1.5 |

Separating the two is the point. Under the old quadratic formula, dropping to 10
levels also dropped the top level to 3,510 XP — a week's work, not a month's.
Now the thresholds are respread across the same XP range, so **the level count
changes how often players level up, not how hard the season is**:

```
10 levels →  0, 634, 1792, 3293, 5070, 7085, 9314, 11736, 14339, 17110
 5 levels →  0, 2139, 6049, 11113, 17110
 3 levels →  0, 2121, 6000            (with top_level_xp: 6000)
```

Set it in the blueprint (`max_level`, `top_level_xp`, `curve_exponent`) or in
`/admin/seasons/:id/edit`. Changing it recomputes every participant's level on
their next recalculation.

**Shrinking a season strands content.** Rewards pinned at level 25 and elite
challenges gated at level 20 can never be reached once the ceiling drops to 10.
`Season#level_config_warnings` surfaces exactly which ones, and the admin page
shows them in an amber banner rather than letting them go quietly dead.

**Season 8 now ships at 10 levels** (was 30). Its rewards were remapped onto
levels 1–10 across both tracks, elite content moved from level 20 to 7, and the
Legacy mission now targets level 10.

### Community goals escalate instead of ending

Clearing a goal no longer stops it. Tier 1 asks for the base target; clearing it
**doubles the target and opens the next tier**, repeating until the season ends.

```
Tier 1: 120 km  →  Tier 2: 240 km  →  Tier 3: 480 km  →  Tier 4: 960 km …
```

- `tier_started_value` records the cumulative total at which the current tier
  opened, so each tier measures only its own stretch — the bar restarts at 0%
  rather than sitting at 100% forever.
- **Milestones repeat per tier.** Clearing a tier clones the previous tier's
  percentages; thresholds derive from the tier, so they scale automatically.
- **Repeat tiers pay coins, scaled by tier** (`tier_coin_reward × tier`), through
  `GrantCommunityTierJob`. One-time cosmetics and badges stay on tier 1 —
  re-pointing them at later tiers would only produce grants the unique index
  rejects. The wallet's `(user, reason_key)` index, keyed by goal and tier, makes
  a retry a no-op.
- Several tiers can clear in one pass (a bulk import, or a long gap between job
  runs). The advance loop is bounded by `MAX_TIER_ADVANCES_PER_RUN` so a
  misconfigured zero target cannot spin.
- `max_tiers` caps escalation; leave it null to keep climbing until the season ends.

Configure in the blueprint under `community_goal`: `tier_coin_reward`, optional
`max_tiers`. Verified on real data — 800 km cleared three tiers in one pass,
paid 200/400/600 coins, and three retries produced exactly three ledger entries.

### Note

`SeasonCommunityGoal#season_community_milestones` carries a display ordering
(`order(:tier, :percent)`), so any `.group(:tier)` aggregate over it needs
`reorder(nil)` first — Postgres rejects the ORDER BY column otherwise. Standard
Rails, but easy to trip over.

---

## 12. Fix: challenges reused across seasons carried their progress over

**Reported:** a challenge added from a previous season to a new one showed as
already finished.

### Two root causes

1. **Progress was global per (user, challenge).** `challenge_participations` had
   one row per user per challenge, with no season. Attaching that challenge to a
   second season reused the same row, so August's progress — and its
   `completed_at` — appeared immediately in September.

   The second half is worse and was invisible: because the row already read as
   completed, `award_completion` never fired again, so the new season's ledger
   never received a completion. The challenge looked finished **and paid no XP**.

2. **The scoring window was global too.** `Challenge#workout_window` used the
   challenge's own dates, so a September season reusing an August challenge
   scored **August workouts**.

### The fix

**Participation is now scoped to a season.** `challenge_participations.season_id`
is null for a challenge joined outside any season (which keeps `/challenges`
working as before) and set for season enrolment. Two partial unique indexes
enforce it — Postgres treats NULLs as distinct, so the season and standalone
cases need separate ones.

**The window now belongs to the season challenge.** `season_challenges.starts_at
/ ends_at` are optional: blank means the whole season, so a reused challenge
automatically measures the new season; set explicitly they carve out a narrower
slice, which is how the four named weeks work. A window outside its season is
rejected — that is almost always dates copied from the season it came from.

Verified: the same challenge in August and September now holds two rows —
`40 km, completed, Aug 1–31` and `0 km, not completed, Sep 1–30` — and completing
the work again in September awards September's XP.

### Two further problems this surfaced

- **`challenge_participations` never had a uniqueness constraint.**
  `ChallengeEnroller` did find-then-create with nothing but timing protecting it,
  and the dev database already contained a duplicate pair. The migration collapses
  duplicates onto the furthest-progressed row (moving attributed workouts across)
  before the new indexes go on.
- **Seasons could not be deleted** once anyone had taken part, because the new
  foreign key had no owning association. `Season has_many :challenge_participations,
  dependent: :destroy` — standalone rows are untouched.

### Behaviour worth knowing

- A standalone participation credits **no** season ledger. Season XP comes only
  from season-scoped participation, which is what season enrolment creates.
- A user can hold both a standalone row and a season row for the same challenge.
  `/challenges/:id` picks one context — the active season owning the challenge,
  else standalone — so the ranking never mixes scores from different months.
- The blueprint's per-challenge `starts_at`/`ends_at` now write to the season
  challenge as well, so next month's blueprint needs no changes.

---

## 13. Fix: the battle pass track rendered broken

**Reported:** the season pass widget looked visually broken and did not scroll.

### Root cause: a stale Tailwind build, not the markup

`app/assets/builds/tailwind.css` was last compiled on **21 June** — before any of
this work existed. Tailwind v4 only emits utilities it finds in the source, so
`overflow-x-auto`, `w-16`, `min-w-max` and `line-clamp-2` were simply **absent
from the stylesheet**. The track had no scroll container and no width constraints,
so it rendered as unstyled overflow.

This affected **every section added for the battle pass**, not just the track —
the dailies grid, community goal, legacy missions and leaderboard were all
missing utilities too. The track was just the most visibly wrong.

The file is gitignored and built at deploy, so nothing was wrong in the repo:

```
bin/rails tailwindcss:build     # one-off
bin/dev                         # web + tailwindcss:watch (Procfile.dev)
```

**Running `bin/rails server` on its own never rebuilds the CSS.** Any new utility
class added since the last build will silently do nothing.

### Markup fixes made alongside

- `border-gray-150` did not exist (Tailwind has no `150` step) — now `border-gray-200`.
- Reward slots had variable heights, so the free and premium rows drifted out of
  alignment wherever a level had only one of them. Every slot is now a fixed
  `h-14`, filled or empty.
- Columns widened `w-16 → w-20` and labels given `line-clamp-2` + `wrap-break-word`,
  so "Legend of August Outfit" wraps inside its box instead of pushing the column open.
- The track bleeds to the card edges (`-mx-5 px-5`) so there is no dead gutter to
  swipe against on mobile, and uses `overscroll-x-contain` to stop the scroll
  chaining to the page.
- A `.battle-pass-track` scrollbar style in `application.css`: macOS hides overlay
  scrollbars until you scroll, so without a visible one the track reads as clipped
  rather than scrollable.
- Leaderboard board tabs now wrap instead of scrolling — that column is half-width
  on desktop and "Elevation" was being clipped off the end.

### Verified

Headless-Chrome audit at 1440px and 390px, signed out and signed in: no element
overflows the viewport outside a scroll container, the page never scrolls
sideways, and the track scrolls (920px of content in an 830px window).

Also caught by the screenshot: the season description still read "Thirty levels"
after the drop to 10.

---

## 14. Season import/export

Building next month should not mean editing YAML by hand in a repo checkout, so
the blueprint loop now closes inside the admin panel.

### The loop

```
/admin/seasons/:id          →  Export blueprint  (optionally shift dates)
      ↓  edit key, name, dates, content
/admin/season_imports/new   →  Validate  →  Import  →  the new season
```

**Export** (`Seasons::BlueprintExporter`) dumps any season to YAML: challenges
with their compound requirements, both reward tracks, legacy missions, daily
pool, cosmetics and the community goal. It defaults to a distinct key and
`status: upcoming`, so a careless import can never overwrite the season being
copied. `shift_to` moves every date by one fixed offset — a week-3 challenge
stays in week 3 — and preserves the original length, so trim `ends_at` when the
new month is shorter.

**Import** (`/admin/season_imports/new`) takes a bundled blueprint, an uploaded
file, or pasted YAML. Paste wins over the other two, so an edited paste is never
silently replaced by the file it came from.

**Template**: `db/seeds/seasons/TEMPLATE.yml` documents every option, including
the full metric list. Downloadable from the import page. It is excluded from the
bundled-blueprint list — it is documentation, not a season.

### Validation before anything is written

`Seasons::BlueprintValidator` checks the whole file and reports **every** problem
at once with the path that caused it:

```
challenges[0].requirements[0].metric: "distnce_km" is not a known metric.
  Did you mean "distance_km"? All metrics: distance_km, duration_hours, …
rewards[1].level: is 99 but the season only has 6 levels, so it could never be granted
```

It catches unknown metrics (with suggestions), rewards and elite gates above the
level ceiling, challenge windows outside the season, duplicate keys, cosmetics
that are referenced but never defined, community metrics that cannot be summed
across people, and milestone percentages out of range. Warnings cover things that
work but probably aren't intended — a daily pool too small to vary, a title
missing from the catalogue.

The import itself is wrapped in a transaction. An import writes across nine
tables; a half-built season would be worse than a rejected one.

### Bugs this surfaced

- **Two title rewards were never actually granted.** `User#add_title` silently
  refuses keys missing from `config/titles.yml`, and `champion` /
  `august_legend_2026` were never added — so the level 10 and 100%-completion
  titles paid out nothing. Both are now in the catalogue, and the validator warns
  about any future omission.
- **"Validate only" did nothing in a real browser.** It answers a POST with a
  200 render, and Turbo drops those unless they redirect. The error path worked
  only because 422 is a status Turbo will render. The form is now
  `data: { turbo: false }`, and a spec asserts it.
- **The button was labelled "1".** `submit_tag`'s first argument is the label, so
  passing `value: "1"` replaced it.
- **Seasons could not be deleted when a community milestone granted a reward.**
  Season destroys its rewards before its community goals, so milestones were left
  pointing at deleted rows. `SeasonReward has_many :season_community_milestones,
  dependent: :nullify` — a milestone outliving its reward is still a milestone.

### Verified

Round-tripped in a real browser: exported Season 8 shifted to September, uploaded
the file back, and got a complete season — 19 challenges, 35 rewards, 5 missions,
12 daily templates, the community goal, week 3 landing on Sep 15–21 — with August
untouched. Invalid blueprints are rejected with both problems named and nothing
written.

---

## 15. Fix: the season form rejected its own values

**Reported:** a validation error on the season's top-level XP on every save.

### Cause: an HTML5 `step` the stored value could not land on

The field was rendered as `number_field :top_level_xp, min: 1, step: 100`. With a
`min` of 1 as the base, the browser only accepts 1, 101, 201… so the stored
**17110** was invalid. Opening the edit form and pressing save — without touching
the field — produced:

> Please enter a valid value. The two nearest valid values are 17101 and 17201.

Nothing reached the server, which is why no server-side validation was involved.
XP has no natural step, so the attribute is simply gone; `min` still bounds it.

The same trap was one edit away in two neighbouring fields, so both are now
`step="any"` with `min`/`max` still enforcing the real bounds:

- `curve_exponent` — would have rejected 1.55.
- `xp_multiplier` — the column stores two decimals, so a multiplier of 1.25 was
  already unsaveable. Pre-existing, same class, fixed while here.

### Also fixed: clearing the curve exponent failed validation

`curve_exponent` is `NOT NULL` with a default of 1.5, but a cleared field submits
`""`, which casts to `nil` and failed `numericality`. A blank optional field now
means "use the default" rather than an error the operator never asked for.

### Guarded

A request spec renders the edit form for a season with awkward values (17110 XP,
1.25 multiplier) and asserts no numeric field carries a `step` that could reject
its own stored value — plus three specs that save the form untouched, with the
exponent cleared, and with the XP cleared.

Verified in a real browser: all four numeric fields report `checkValidity() ==
true` untouched, and changing the level count from 10 to 12 saves and rebuilds
the curve.
