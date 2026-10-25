# frozen_string_literal: true

# A player's RSVP to an event, and their result once a workout is linked.
class EventParticipationResource < ApplicationResource
  attributes :id, :event_id, :bib_number, :notes, :workout_id

  attribute(:status) { |participation| participation.completed? ? "completed" : "going" }
  attribute(:selected_distance_km) { |participation| participation.selected_distance_km&.to_f }
  attribute(:workout) { |participation| participation.workout && AttachedWorkoutResource.new(participation.workout).serializable_hash }
  attribute(:pace_min_per_km) { |participation| participation.pace_per_km&.round(2) }
end
