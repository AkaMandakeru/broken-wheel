# Sports Communities MVP - Implementation Plan

## Executive Summary

A Rails 8 monolith PWA for sports communities with weekly/monthly challenges, friend invitations, rankings, and integrations with Strava, Garmin, and other providers. Mobile-first, Strava-inspired design.

---

## Tech Stack Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Auth** | Devise | Industry standard, email confirmation, sessions, password reset |
| **CSS** | Tailwind CSS via CDN or Propshaft | Strava-like clean design, mobile-first utilities, orange accent |
| **Icons** | Lucide Icons (SVG) or Heroicons | Lightweight, clean, Strava-like aesthetic |
| **Forms** | Rails form_with + Stimulus | Native Rails, no heavy JS framework |
| **PWA** | Existing manifest + service worker | Already scaffolded, enhance for offline |
| **Background Jobs** | Solid Queue | Already in Gemfile, for data sync |

---

## Data Model

### Core Entities

```
User (Devise)
├── email:string (required, from Devise)
├── first_name:string (required)
├── last_name:string (required)
├── nickname:string
├── document:string
├── phone:string
├── blood_type:string
├── address:string
├── avatar:active_storage
├── confirmed_at:datetime
├── sports:[] (run, bike, soccer - jsonb or join table)
└── preferences:jsonb (age_range, location, etc.)

UserSportConnection (OAuth tokens for providers)
├── user_id
├── provider:enum (strava, garmin, etc.)
├── access_token:encrypted
├── refresh_token:encrypted
├── expires_at
└── external_id:string

Challenge
├── title:string
├── description:text
├── challenge_type:enum (weekly, monthly, yearly)
├── sport:enum (run, bike)
├── target_value:decimal (km or minutes)
├── target_unit:enum (km, minutes)
├── starts_at:datetime
├── ends_at:datetime
└── status:enum (upcoming, active, completed)

ChallengeParticipation
├── challenge_id
├── user_id
├── invite_code:string (unique, for sharing)
├── invited_by_id (nullable)
├── points:integer (default 0)
├── progress_value:decimal (km/minutes completed)
└── completed_at:datetime (nullable)

Workout (imported activities)
├── user_id
├── challenge_participation_id (nullable - can count for multiple)
├── provider:enum (strava, garmin, manual)
├── external_id:string
├── sport:enum
├── distance_km:decimal
├── duration_minutes:integer
├── workout_date:date
└── raw_data:jsonb

Badge
├── name:string
├── icon:string (or emoji for MVP)
├── description:text
└── badge_type:enum (challenge_completion, milestone, etc.)

UserBadge
├── user_id
├── badge_id
├── challenge_id (nullable)
└── earned_at:datetime

Club (simple for MVP)
├── name:string
├── description:text
├── sport:enum
├── created_by_id
└── member_count:integer (counter cache)

ClubMembership
├── club_id
├── user_id
└── role:enum (admin, member)

TimelinePost (activity feed, scoped per challenge - visible to all challenge participants)
├── user_id
├── challenge_id (required - all participants see posts from this challenge)
├── workout_id (optional - attached to a workout when implemented)
├── content:text (comment/description)
├── images:active_storage (one or more pictures)
├── metadata:jsonb (pace, elevation, heart rate, etc. - flexible for future)
└── created_at

TimelinePostComment (comments on posts)
├── timeline_post_id
├── user_id
├── content:text
└── created_at
```

---

## Implementation Phases

### Phase 1: Foundation (Auth + Layout)
**Estimated: 2-3 hours**

1. Add Devise + dependencies to Gemfile
2. Generate User model with Devise (`rails g devise User`)
3. Add `first_name`, `last_name`, `nickname`, `document`, `phone`, `blood_type`, `address`, `avatar` to User (migration; first_name, last_name required)
4. Configure Devise: confirmable, lockable, timeoutable
5. Generate Devise views (`rails g devise:views`)
6. Customize login/register views - Strava-inspired clean layout
7. Add Tailwind CSS (via CDN for speed, or add tailwindcss-rails)
8. Create application layout with:
   - Mobile-first responsive nav (hamburger on mobile, full on desktop)
   - Orange accent (#FC4C02 - Strava orange)
   - Footer
9. Set root to challenges or dashboard (after login)

### Phase 2: Profile Page
**Estimated: 2 hours**

1. Create `ProfilesController` (or `UsersController` for `current_user`)
2. Profile form: first_name, last_name, nickname, document, phone, blood_type, address, avatar upload (Active Storage)
3. Sport preferences: checkboxes (run, bike, soccer)
4. UserSportConnection model + CRUD for connect/remove
5. Placeholder for OAuth flow (Strava/Garmin) - stub "Connect Strava" button
6. Badges section: list `UserBadge` with icon + challenge name
7. Route: `GET /profile`, `PATCH /profile`

### Phase 3: Challenges & Workouts
**Estimated: 3-4 hours**

1. Challenge model + migrations
2. ChallengeParticipation model (with invite_code)
3. Workout model
4. ChallengesController: index (weekly, monthly, yearly tabs), show (rank + progress)
5. WorkoutsController: index with:
   - Active challenges list
   - Progress bars (orange, clean)
   - Workout count, unique days count
6. Seed challenges (weekly run 20km, monthly bike 200km, etc.)
7. Progress bar component (Stimulus or partial)
8. Join challenge flow
9. Invite flow: generate link with invite_code, share to email/whatsapp

### Phase 4: Data Import & Badges
**Estimated: 2-3 hours**

1. Workout import service (placeholder for Strava webhook/API)
2. Manual workout form (for MVP testing)
3. Job to sync workouts from providers (stub)
4. Badge model + UserBadge
5. Logic: when ChallengeParticipation.progress_value >= target → complete, award badge
6. Badge icons: simple SVG or emoji (🏃 🚴 🏆)

### Phase 4b: Timeline (Challenge Feed)
**Estimated: 2 hours**

1. TimelinePost model (challenge_id, user_id, workout_id optional, content, images, metadata)
2. TimelinePostComment model
3. TimelineController or nested under Challenges: `challenges/:id/timeline`
4. Timeline page: feed of posts from challenge participants (chronological)
5. Create post form: content, images, optional workout attachment
6. Comments on posts (create, list)
7. Access control: only challenge participants can view/post

### Phase 5: Communities/Clubs
**Estimated: 2 hours**

1. Club model + ClubMembership
2. ClubsController: index with simple relevance (filter by user's sports)
3. "Create Club" form (name, sport, description)
4. Join/leave club
5. Placeholder for future: age, geolocation, preferences algorithm

### Phase 6: Polish & PWA
**Estimated: 1-2 hours**

1. Enable PWA manifest + service worker routes
2. Update manifest: theme_color orange, proper icons
3. Add meta tags for mobile
4. Responsive polish on all screens
5. Email templates for confirmation (Devise)

---

## Screen Specifications

### 1. Login/Register
- Split or tabbed: Login | Register
- Email, password, first_name, last_name (required); nickname, document, phone, blood_type, address, avatar (optional)
- Avatar upload optional on register
- "Confirm your email" message after register
- Clean, centered form, orange CTA buttons

### 2. Profile
- Avatar (editable), first_name, last_name, nickname, document, phone, blood_type, address
- Sports: Run, Bike, Soccer checkboxes
- Connected apps: Strava, Garmin (Connect / Disconnect)
- Badges grid below (icon + name)

### 3. Workouts
- Header: "X workouts" | "Y days"
- Active challenges: card per challenge, progress bar (orange)
- List of recent workouts (date, sport, distance, duration)

### 4. Communities/Clubs
- List of clubs (card: name, sport, members)
- Filter by sport (from user prefs)
- "Create Club" button
- Join/Leave

### 5. Challenges
- Tabs: Weekly | Monthly | Yearly | Events (placeholder)
- Challenge cards: title, sport, target, dates, "Join" or "In Progress"
- Click → Challenge detail: rank table, progress bars, invite button, link to Timeline

### 6. Timeline (Challenge Feed)
- Scoped to a single challenge - all participants see the same feed
- Post form: text (comment/description), image upload(s), optional link to workout
- Feed: chronological list of posts (avatar, name, content, images, workout summary if attached)
- Each post: comment thread (create/view comments)
- Strava-like: share after workout with pictures and notes; others in the challenge see and react

---

## Routes Structure

```ruby
root "challenges#index"

devise_for :users

authenticated :user do
  get "profile", to: "profiles#show"
  patch "profile", to: "profiles#update"

  resources :workouts, only: [:index, :create]
  resources :challenges, only: [:index, :show] do
    member do
      post :join
      get :invite
    end
    resources :timeline_posts, only: [:index, :create], path: "timeline" do
      resources :comments, only: [:create], controller: "timeline_post_comments"
    end
  end

  resources :clubs, only: [:index, :show, :create] do
    member do
      post :join
      delete :leave
    end
  end
end
```

---

## CSS / Design System

- **Primary**: Orange `#FC4C02` (Strava-like)
- **Neutral**: Gray scale for text, borders
- **Typography**: System font stack or Inter
- **Spacing**: Consistent 4/8/16/24px
- **Cards**: White bg, subtle shadow, rounded corners
- **Progress bar**: Orange fill, gray track, rounded

---

## File Structure (New Files)

```
app/
  controllers/
    profiles_controller.rb
    workouts_controller.rb
    challenges_controller.rb
    clubs_controller.rb
    timeline_posts_controller.rb
    timeline_post_comments_controller.rb
  models/
    user.rb (Devise)
    user_sport_connection.rb
    challenge.rb
    challenge_participation.rb
    workout.rb
    badge.rb
    user_badge.rb
    club.rb
    club_membership.rb
    timeline_post.rb
    timeline_post_comment.rb
  views/
    layouts/
      application.html.erb (updated)
    profiles/
    workouts/
    challenges/
    clubs/
    timeline_posts/
    shared/
      _progress_bar.html.erb
      _nav.html.erb
  services/
    workout_import_service.rb (stub)
  jobs/
    sync_strava_workouts_job.rb (stub)
db/
  migrate/
    ... (multiple migrations)
```

---

## Dependencies to Add

```ruby
# Gemfile
gem "devise"
gem "tailwindcss-rails" # or use CDN
gem "omniauth-strava"   # Phase 2 - OAuth (can defer)
gem "omniauth-garmin"   # Phase 2 - OAuth (can defer)
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| OAuth complexity | Stub "Connect" buttons, implement in v1.1 |
| Strava rate limits | Cache, batch sync, respect limits |
| PWA offline | Start with online-only, add offline later |

---

## Next Steps

1. Review and approve this plan
2. Execute Phase 1 (Auth + Layout)
3. Proceed sequentially through phases
4. Test each phase before moving on

---

*Document created for Sports Communities MVP. Last updated: 2025-03-15*
