# frozen_string_literal: true

# One entry of the player's training log, typed in or imported from Strava.
class WorkoutResource < ApplicationResource
  attributes :id, :sport, :provider, :external_id, :start_time_known

  attribute(:workout_date) { |workout| workout.workout_date&.iso8601 }
  attribute(:distance_km) { |workout| workout.distance_km&.to_f }

  attribute :duration do |workout|
    { minutes: workout.duration_minutes,
      moving_seconds: workout.moving_time_seconds,
      elapsed_seconds: workout.elapsed_time_seconds }
  end

  attribute(:pace_seconds_per_km) { |workout| workout.pace_seconds_per_km&.round }

  # Wall-clock "HH:MM" where the workout happened; null when the player didn't
  # give one (the stored placeholder only keeps ordering stable).
  attribute :start_time do |workout|
    workout.started_at_local&.strftime("%H:%M") if workout.start_time_known
  end

  attribute(:created_at) { |workout| workout.created_at.iso8601 }
end
