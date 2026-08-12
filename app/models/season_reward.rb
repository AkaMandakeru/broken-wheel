class SeasonReward < ApplicationRecord
  belongs_to :season
  has_many :season_reward_grants, dependent: :destroy

  # Nullify, not destroy: a milestone outliving its reward is still a milestone,
  # it just stops granting one. Without this, deleting a season fails — Season
  # destroys its rewards before its community goals, leaving milestones pointing
  # at rows that are already gone.
  has_many :season_community_milestones, dependent: :nullify

  REWARD_TYPES = %w[title badge theme coins cosmetic xp_boost].freeze
  TRACKS       = %w[free premium].freeze

  # How a reward is earned. `level` is the battle pass track; the rest are
  # parallel progressions that grant through the same idempotent path.
  UNLOCK_KINDS = %w[level legacy completion_tier medal_fragments community].freeze

  validates :reward_type, inclusion: { in: REWARD_TYPES }
  validates :track, inclusion: { in: TRACKS }
  validates :unlock_kind, inclusion: { in: UNLOCK_KINDS }
  validates :reward_key, presence: true
  validates :level, numericality: { greater_than: 0 }, allow_nil: true
  validates :level, presence: true, if: -> { unlock_kind == "level" }
  validates :unlock_value, presence: true, unless: -> { unlock_kind == "level" }
  validates :coins, numericality: { greater_than_or_equal_to: 0 }

  scope :for_level, ->(level) { where(unlock_kind: "level").where(level: ..level) }
  scope :on_track, ->(premium) { where(track: premium ? TRACKS : [ "free" ]) }
  scope :by_unlock, ->(kind, value) { where(unlock_kind: kind).where(unlock_value: ..value) }

  before_validation :default_unlock_value

  def premium?
    track == "premium"
  end

  private

  # Level rewards keep `unlock_value` in sync with `level` so a single query
  # shape serves every unlock kind.
  def default_unlock_value
    self.unlock_value = level if unlock_kind == "level" && level.present?
  end
end
