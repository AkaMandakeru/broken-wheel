# frozen_string_literal: true

# Builders for season/challenge specs. The suite uses plain `create!` rather
# than FactoryBot, so these keep the setup in each example short enough to read.
module SeasonBuilders
  def build_user(**overrides)
    User.create!({
      first_name: "Test",
      last_name: "Runner",
      email: "runner-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    }.merge(overrides))
  end

  def build_season(**overrides)
    Season.create!({
      key: "season-#{SecureRandom.hex(4)}",
      name: "Test Season",
      status: "active",
      theme: "legacy",
      starts_at: Date.new(2026, 8, 1),
      ends_at: Date.new(2026, 8, 31),
      time_zone: "America/Sao_Paulo",
      max_level: 30,
      level_curve: Seasons::LevelCurve.build(30)
    }.merge(overrides))
  end

  # A workout with a real clock time by default, so hour-based metrics can see it.
  def build_workout(user, date:, km: 5, minutes: 30, sport: "run", hour: 9, minute: 0,
                    known_time: true, elevation: nil, calories: nil, elapsed: nil, route: nil)
    started = Time.utc(date.year, date.month, date.day, hour, minute)
    moving = minutes * 60

    Workout.create!(
      user: user,
      sport: sport,
      distance_km: km,
      duration_minutes: minutes,
      workout_date: date,
      started_at_local: started,
      started_at: started,
      start_time_known: known_time,
      start_minute_of_day: known_time ? (hour * 60) + minute : nil,
      moving_time_seconds: moving,
      elapsed_time_seconds: elapsed || moving,
      elevation_gain_m: elevation,
      calories: calories,
      route_signature: route,
      provider: "manual"
    )
  end

  def build_challenge(key:, requirements:, sport: nil, starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 31))
    challenge = Challenge.create!(
      key: key,
      title: key.humanize,
      challenge_type: "custom",
      sport: sport,
      status: "active",
      starts_at: starts_at,
      ends_at: ends_at,
      target_value: requirements.first[:target],
      target_unit: "km"
    )

    requirements.each_with_index do |requirement, position|
      challenge.challenge_requirements.create!(
        metric: requirement[:metric],
        target: requirement[:target],
        options: requirement[:options] || {},
        position: position
      )
    end

    challenge
  end

  def metric_context(user, window:, season: nil, participation: nil, options: {}, sport: nil)
    ChallengeMetrics::Context.new(
      user: user, window: window, season: season,
      participation: participation, options: options, sport: sport
    )
  end

  # August 2026 in full — the reference season's window.
  def august
    Date.new(2026, 8, 1)..Date.new(2026, 8, 31)
  end
end

RSpec.configure { |config| config.include SeasonBuilders }
