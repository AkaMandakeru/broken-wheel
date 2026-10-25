# frozen_string_literal: true

# A workout as it appears attached to something else — a timeline post or an
# event result — rather than in the player's own workout list.
class AttachedWorkoutResource < ApplicationResource
  attributes :id, :sport, :workout_date, :duration_minutes

  attribute(:distance_km) { |workout| workout.distance_km&.to_f }
end
