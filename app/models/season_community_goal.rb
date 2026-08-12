# frozen_string_literal: true

# A goal the whole community pushes toward together. `current_value` is a cached
# aggregate refreshed by AggregateCommunityGoalsJob, never incremented per
# workout — so it can be rebuilt at any time and cannot drift.
#
# Goals escalate: clearing tier 1 doubles the target and opens tier 2, and so on
# until the season ends. `tier_started_value` records the cumulative total at
# which the current tier opened, so each tier measures only its own stretch
# rather than the season total.
class SeasonCommunityGoal < ApplicationRecord
  belongs_to :season
  has_many :season_community_milestones, -> { order(:tier, :percent) }, dependent: :destroy

  TARGET_MODES = %w[fixed per_participant].freeze
  TIER_MULTIPLIER = 2

  # Stops a misconfigured goal (base target of nil or 0) from advancing forever
  # inside a single job run.
  MAX_TIER_ADVANCES_PER_RUN = 20

  validates :key, presence: true, uniqueness: { scope: :season_id }
  validates :metric, presence: true, inclusion: { in: ->(_g) { ChallengeMetrics.keys } }
  validates :target_mode, inclusion: { in: TARGET_MODES }
  validates :target_value, numericality: { greater_than: 0 }
  validates :tier, numericality: { greater_than: 0 }
  validates :tier_coin_reward, numericality: { greater_than_or_equal_to: 0 }

  before_validation :default_base_target

  def current_milestones
    season_community_milestones.where(tier: tier)
  end

  # A fixed headline number ("10,000,000 km") is unreachable for a community of
  # any realistic size, and an unreachable bar stops motivating after week one.
  # `per_participant` keeps the goal ambitious but attainable as the season grows.
  def base_target
    configured = base_target_value.presence || target_value
    return configured.to_f if target_mode == "fixed"

    participants = season.season_participations.count
    [ (participants * per_participant.to_f).round(2), per_participant.to_f ].max
  end

  # What this tier alone asks for — doubling with each tier cleared.
  def effective_target
    (base_target * (TIER_MULTIPLIER**(tier - 1))).round(2)
  end

  # Distance covered since this tier opened.
  def tier_progress
    [ current_value.to_f - tier_started_value.to_f, 0 ].max.round(2)
  end

  def percent_complete
    target = effective_target
    return 0 if target.zero?

    [ ((tier_progress / target) * 100).round, 100 ].min
  end

  def tier_complete?
    effective_target.positive? && tier_progress >= effective_target
  end

  def final_tier?
    max_tiers.present? && tier >= max_tiers
  end

  # Total cleared across every tier so far — what the "level 3" badge counts.
  def tiers_cleared
    tier - 1
  end

  def display_title
    I18n.t("seasons.community.goals.#{key}.title", default: key.to_s.humanize)
  end

  def display_description
    I18n.t("seasons.community.goals.#{key}.description", default: "")
  end

  def unit
    ChallengeMetrics.unit_for(metric)
  end

  # Coins each participant earns for clearing the current tier. Scaling with the
  # tier keeps a bigger goal worth the bigger effort.
  def tier_payout
    tier_coin_reward * tier
  end

  private

  def default_base_target
    self.base_target_value = target_value if base_target_value.blank?
  end
end
