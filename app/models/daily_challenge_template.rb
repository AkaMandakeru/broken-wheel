# frozen_string_literal: true

# The pool a user's three daily challenges are drawn from. Templates may be
# scoped to a season or shared across all of them (season_id nil).
class DailyChallengeTemplate < ApplicationRecord
  belongs_to :season, optional: true
  has_many :daily_challenge_assignments, dependent: :destroy

  validates :key, presence: true, uniqueness: { scope: :season_id }
  validates :metric, presence: true, inclusion: { in: ->(_t) { ChallengeMetrics.keys } }
  validates :target, numericality: { greater_than: 0 }
  validates :weight, numericality: { greater_than: 0 }
  validates :xp_reward, :coin_reward, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :for_season, ->(season) { where(season_id: [ season.id, nil ]) }
  scope :timeless, -> { where(requires_start_time: false) }

  before_validation :infer_start_time_requirement

  def display_title
    I18n.t("dailies.#{key}.title", default: key.to_s.humanize)
  end

  def display_description
    I18n.t(
      "dailies.#{key}.description",
      count: target.to_f == target.to_i ? target.to_i : target.to_f,
      default: display_title
    )
  end

  def comparator
    ChallengeMetrics.comparator_for(metric)
  end

  def satisfied_by?(value)
    ChallengeMetrics.satisfied?(metric, value, target)
  end

  def percent_of(value)
    return satisfied_by?(value) ? 100 : 0 if comparator == :lte
    return 0 if target.to_f.zero?

    [ ((value.to_f / target.to_f) * 100).round, 100 ].min
  end

  private

  # Keeps the flag honest so the assigner's filtering can be trusted.
  def infer_start_time_requirement
    return unless ChallengeMetrics.exists?(metric)

    self.requires_start_time = true if ChallengeMetrics.requires_start_time?(metric)
  end
end
