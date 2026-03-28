class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :challenge_participation, optional: true

  attr_accessor :distance_km_input, :distance_m_input, :duration_hours_input, :duration_minutes_input, :duration_seconds_input

  before_validation :assign_distance_and_duration

  private

  def assign_distance_and_duration
    if distance_km_input.present? || distance_m_input.present?
      self.distance_km = distance_km_input.to_f + (distance_m_input.to_f / 1000.0)
    end

    if duration_hours_input.present? || duration_minutes_input.present? || duration_seconds_input.present?
      self.duration_minutes = (duration_hours_input.to_i * 60) + duration_minutes_input.to_i + (duration_seconds_input.to_f / 60.0).round
    end
  end
end
