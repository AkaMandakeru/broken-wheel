# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Default admin user (development only)
#   Override with ADMIN_EMAIL / ADMIN_PASSWORD env vars if desired.
# ---------------------------------------------------------------------------

if Rails.env.development?
  admin_email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
  admin_password = ENV.fetch("ADMIN_PASSWORD", "password")

  admin = User.find_or_initialize_by(email: admin_email)
  admin.assign_attributes(
    first_name: "Admin",
    last_name: "User",
    password: admin_password,
    password_confirmation: admin_password,
    admin: true,
    confirmed_at: admin.confirmed_at || Time.current
  )
  admin.save!

  puts "👤 Admin user ready: #{admin_email} / #{admin_password}"
end

# ---------------------------------------------------------------------------
# Default (system) Challenges
#   Titles/descriptions are translated via config/locales
#   (challenges.defaults.<key>.*); the English text below is only a fallback.
# ---------------------------------------------------------------------------

def upsert_default_challenge(key:, challenge_type:, sport:, target_value:, target_unit:, title:, description:)
  if challenge_type == "weekly"
    week = Challenge.current_week_window
    starts_at = week.begin
    ends_at = week.end
  else
    starts_at = Date.current.beginning_of_month
    ends_at = Date.current.end_of_month
  end

  challenge = Challenge.find_or_initialize_by(key: key)
  challenge.update!(
    challenge_type: challenge_type,
    sport: sport,
    target_value: target_value,
    target_unit: target_unit,
    title: title,
    description: description,
    starts_at: starts_at,
    ends_at: ends_at,
    status: "active"
  )
end

DEFAULT_CHALLENGES = [
  { key: "weekly_distance_run",   challenge_type: "weekly",  sport: "run",  target_value: 20,  target_unit: "km",    title: "Weekly Run 20km",    description: "Run 20km this week." },
  { key: "monthly_distance_run",  challenge_type: "monthly", sport: "run",  target_value: 80,  target_unit: "km",    title: "Monthly Run 80km",   description: "Run 80km this month." },
  { key: "weekly_count_run",      challenge_type: "weekly",  sport: "run",  target_value: 4,   target_unit: "times", title: "Weekly Run x4",      description: "Complete 4 runs this week." },
  { key: "monthly_count_run",     challenge_type: "monthly", sport: "run",  target_value: 16,  target_unit: "times", title: "Monthly Run x16",    description: "Complete 16 runs this month." }
].freeze

DEFAULT_CHALLENGES.each { |attrs| upsert_default_challenge(**attrs) }

# ---------------------------------------------------------------------------
# Example Season (Summer Miles) — DEVELOPMENT ONLY.
#   Real seasons are created by admins in /admin/seasons, so this demo season
#   is never seeded in production.
# ---------------------------------------------------------------------------

if Rails.env.development?
  season = Season.find_or_initialize_by(key: "summer_miles")
  season.update!(
    name: "Summer Miles",
    description: "Rack up the miles this month. Complete challenges, climb the ranks and unlock summer rewards.",
    theme: "summer",
    status: "active",
    starts_at: Date.current.beginning_of_month,
    ends_at: Date.current.end_of_month,
    xp_multiplier: 1.0
  )

  {
    "weekly_distance_run" => { position: 0, xp_reward: 150, required: true },
    "monthly_distance_run" => { position: 1, xp_reward: 300, required: true },
    "weekly_count_run" => { position: 2, xp_reward: 120, required: false }
  }.each do |challenge_key, attrs|
    challenge = Challenge.find_by(key: challenge_key)
    next unless challenge

    sc = season.season_challenges.find_or_initialize_by(challenge: challenge)
    sc.update!(attrs)
  end

  [
    { level: 2, reward_type: "title", reward_key: "trail_hunter", name: "Trail Hunter" },
    { level: 3, reward_type: "badge", reward_key: "summer_miles_finisher", name: "Summer Miles Badge" },
    { level: 5, reward_type: "theme", reward_key: "summer", name: "Summer Profile Theme" }
  ].each do |attrs|
    season.season_rewards.find_or_initialize_by(level: attrs[:level], reward_type: attrs[:reward_type]).update!(attrs)
  end

  # ---------------------------------------------------------------------------
  # Battle pass season (Season 8 — Legacy of Champions)
  #   Built from db/seeds/seasons/*.yml. The importer is idempotent, so this is
  #   safe to re-run, and a new month is a new blueprint file rather than code.
  # ---------------------------------------------------------------------------
  Seasons::BlueprintImporter.call("season_8_legacy_of_champions")
  puts "🏆 Season 8 (Legacy of Champions) imported."
end
