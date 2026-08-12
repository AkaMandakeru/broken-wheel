# frozen_string_literal: true

# The single question every season mechanic asks:
#
#   "Given a user, a time window and some options, what is the value of metric X?"
#
# Daily, weekly, monthly, elite and hidden challenges, legacy missions, season
# objectives and leaderboards all resolve through this registry, so a new kind of
# goal is a new metric class rather than a new subsystem.
module ChallengeMetrics
  class UnknownMetric < StandardError; end

  REGISTRY = {
    "distance_km"             => Metrics::DistanceKm,
    "duration_hours"          => Metrics::DurationHours,
    "activity_count"          => Metrics::ActivityCount,
    "active_days"             => Metrics::ActiveDays,
    "longest_activity_km"     => Metrics::LongestActivityKm,
    "activities_over_km"      => Metrics::ActivitiesOverKm,
    "consecutive_days"        => Metrics::ConsecutiveDays,
    "weeks_with_activity"     => Metrics::WeeksWithActivity,
    "elevation_gain_m"        => Metrics::ElevationGain,
    "calories"                => Metrics::Calories,
    "start_before_hour"       => Metrics::StartBeforeHour,
    "start_after_hour"        => Metrics::StartAfterHour,
    "beat_previous_day"       => Metrics::BeatPreviousDay,
    "personal_record"         => Metrics::PersonalRecord,
    "fastest_5k_seconds"      => Metrics::Fastest5k,
    "uninterrupted_activity"  => Metrics::UninterruptedActivity,
    "new_route"               => Metrics::NewRoute,
    "club_member"             => Metrics::ClubMember,
    "club_workout_count"      => Metrics::ClubWorkoutCount,
    "battle_pass_level"       => Metrics::BattlePassLevel,
    "completed_weeklies"      => Metrics::CompletedWeeklies,
    "daily_challenges_done"   => Metrics::DailyChallengesDone,
    "perfect_daily_days"      => Metrics::PerfectDailyDays,
    "timeline_posts"          => Metrics::TimelinePosts
  }.freeze

  module_function

  def fetch(key)
    REGISTRY.fetch(key.to_s) { raise UnknownMetric, "Unknown challenge metric: #{key.inspect}" }
  end

  def exists?(key)
    REGISTRY.key?(key.to_s)
  end

  def keys
    REGISTRY.keys
  end

  # `context` is a ChallengeMetrics::Context. Returns a Numeric.
  def call(key, context)
    fetch(key).call(context)
  end

  def unit_for(key)
    fetch(key).unit
  end

  # :gte for "reach at least N", :lte for "get under N" (times, paces).
  def comparator_for(key)
    fetch(key).comparator
  end

  # True when a metric can only be satisfied by workouts carrying a real clock
  # time — used to keep unwinnable dailies away from manual-entry users.
  def requires_start_time?(key)
    fetch(key).requires_start_time?
  end

  def satisfied?(key, value, target)
    if comparator_for(key) == :lte
      value.present? && value.to_f.positive? && value.to_f <= target.to_f
    else
      value.to_f >= target.to_f
    end
  end
end
