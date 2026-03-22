class Badge < ApplicationRecord
  has_many :user_badges
  has_many :users, through: :user_badges

  CATEGORIES = {
    "workout_count"   => "Workout Count",
    "distance_pr"     => "Personal Records",
    "distance_count"  => "Distance Milestones",
    "streak"          => "Consistency Streaks",
    "pace"            => "Pace Achievements"
  }.freeze

  scope :workout_count,  -> { where(badge_type: "workout_count").order(:threshold_value) }
  scope :distance_pr,    -> { where(badge_type: "distance_pr").order(:threshold_distance) }
  scope :distance_count, -> { where(badge_type: "distance_count").order(:threshold_distance, :threshold_value) }
  scope :streak,         -> { where(badge_type: "streak").order(:threshold_value) }
  scope :pace,           -> { where(badge_type: "pace").order(:threshold_distance, :threshold_value) }
end
