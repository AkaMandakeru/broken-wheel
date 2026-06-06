class EventParticipation < ApplicationRecord
  belongs_to :user
  belongs_to :event, counter_cache: true
  belongs_to :workout, optional: true

  validates :user_id, uniqueness: { scope: :event_id }
  validate :workout_belongs_to_user
  validate :selected_distance_offered

  # Result data is derived from the linked Strava workout.
  delegate :distance_km, :duration_minutes, :workout_date, to: :workout, allow_nil: true

  # A participation starts as an RSVP ("going") and becomes "completed"
  # once the user links the workout they did at the event.
  def completed?
    workout_id.present?
  end

  def going?
    workout_id.blank?
  end

  def pace_per_km
    return nil if workout.nil? || distance_km.to_f.zero? || duration_minutes.to_f.zero?

    duration_minutes.to_f / distance_km.to_f
  end

  def track_polyline
    workout&.raw_data&.dig("map", "summary_polyline").presence ||
      workout&.raw_data&.dig("map", "polyline").presence
  end

  private

  def workout_belongs_to_user
    return if workout.nil? || workout.user_id == user_id

    errors.add(:workout, :invalid)
  end

  # When the event offers specific distances, the participant must pick one of them.
  def selected_distance_offered
    return if event.nil? || event.distances.blank?

    if selected_distance_km.blank?
      errors.add(:selected_distance_km, :blank)
    elsif event.distances.map(&:to_f).exclude?(selected_distance_km.to_f)
      errors.add(:selected_distance_km, :inclusion)
    end
  end
end
