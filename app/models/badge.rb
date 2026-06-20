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

  # --- Localized display text ----------------------------------------------
  # Translations are keyed off the badge's stable attributes (type + thresholds)
  # so the seed catalogue never needs per-row translation columns. When a
  # translation is missing for the current locale we fall back to the English
  # value stored in the database, so English keeps working with no locale entries.

  def display_name
    translated_name.presence || name
  end

  def display_title
    translated_title.presence || title
  end

  def display_description
    I18n.t("badges.descriptions.#{badge_type}", default: description.to_s, **description_vars)
  end

  private

  def translated_name
    case badge_type
    when "workout_count" then I18n.t("badges.workout_count.names.#{threshold_value.to_i}", default: nil)
    when "distance_pr"   then I18n.t("badges.distance_pr.names.#{threshold_distance.to_i}", default: nil)
    when "streak"        then I18n.t("badges.streak.names.#{threshold_value.to_i}", default: nil)
    when "distance_count"
      compose(I18n.t("badges.series.#{threshold_distance.to_i}", default: nil),
              I18n.t("badges.count_tiers.#{threshold_value.to_i}", default: nil))
    when "pace"
      compose(I18n.t("badges.pace.labels.#{threshold_distance.to_i}", default: nil),
              I18n.t("badges.pace.names.#{pace_key}", default: nil))
    end
  end

  def translated_title
    case badge_type
    when "workout_count"  then I18n.t("badges.workout_count.titles.#{threshold_value.to_i}", default: nil)
    when "distance_pr"    then I18n.t("badges.distance_pr.titles.#{threshold_distance.to_i}", default: nil)
    when "streak"         then I18n.t("badges.streak.titles.#{threshold_value.to_i}", default: nil)
    when "distance_count" then I18n.t("badges.count_tiers.#{threshold_value.to_i}", default: nil)
    when "pace"           then I18n.t("badges.pace.titles.#{pace_key}", default: nil)
    end
  end

  def description_vars
    case badge_type
    when "workout_count"  then { count: threshold_value.to_i }
    when "distance_pr"    then { distance: threshold_distance.to_i }
    when "distance_count" then { count: threshold_value.to_i, distance: threshold_distance.to_i }
    when "streak"         then { weeks: threshold_value.to_i }
    when "pace"           then { distance: threshold_distance.to_i, pace: formatted_pace }
    else {}
    end
  end

  # Only compose when both halves are translated; otherwise fall back to the DB name.
  def compose(first, second)
    (first && second) ? "#{first} #{second}" : nil
  end

  # 6.0 => 60, 5.5 => 55 … gives integer-safe i18n keys for pace tiers.
  def pace_key
    (threshold_value.to_f * 10).round
  end

  def formatted_pace
    value = threshold_value.to_f
    format("%d:%02d/km", value.to_i, ((value % 1) * 60).round)
  end
end
