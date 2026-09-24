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
  #
  # `participation` is the odd one out: it is earned by being in the season at
  # all, so it has no threshold to clear. Its optional joined_from/joined_until
  # window narrows it to people who joined inside that period.
  UNLOCK_KINDS = %w[level legacy completion_tier medal_fragments community participation].freeze

  # Kinds with no numeric threshold behind them.
  THRESHOLDLESS_KINDS = %w[level participation].freeze

  validates :reward_type, inclusion: { in: REWARD_TYPES }
  validates :track, inclusion: { in: TRACKS }
  validates :unlock_kind, inclusion: { in: UNLOCK_KINDS }
  validates :reward_key, presence: true
  validates :level, numericality: { greater_than: 0 }, allow_nil: true
  validates :level, presence: true, if: -> { unlock_kind == "level" }
  validates :unlock_value, presence: true, unless: -> { THRESHOLDLESS_KINDS.include?(unlock_kind) }
  validates :coins, numericality: { greater_than_or_equal_to: 0 }
  validate :join_window_is_ordered
  validate :claimable_only_for_participation

  scope :for_level, ->(level) { where(unlock_kind: "level").where(level: ..level) }
  scope :on_track, ->(premium) { where(track: premium ? TRACKS : [ "free" ]) }
  scope :by_unlock, ->(kind, value) { where(unlock_kind: kind).where(unlock_value: ..value) }
  scope :participation, -> { where(unlock_kind: "participation") }
  # Offered rather than pushed: the player takes it from their locker.
  scope :claimable, -> { participation.where(claimable: true) }
  scope :pushed, -> { participation.where(claimable: false) }

  # Where each of these cosmetics is first offered, keyed by cosmetic key. A
  # cosmetic handed out by several seasons resolves to its earliest unlock —
  # that is the first chance a player actually has at it.
  def self.cosmetic_unlocks_for(keys)
    keys = Array(keys)
    return {} if keys.empty?

    where(reward_type: "cosmetic", reward_key: keys)
      .includes(:season)
      .order(:unlock_value)
      .group_by(&:reward_key)
      .transform_values(&:first)
  end

  before_validation :default_unlock_value

  def premium?
    track == "premium"
  end

  def participation?
    unlock_kind == "participation"
  end

  # Only a participation reward can be claimed. Everything else has a threshold
  # the player has to clear, and a Claim button would skip it.
  def claimable_by_hand?
    participation? && claimable?
  end

  # Does someone who joined at `joined_at` qualify? An open end is what makes
  # "everyone, from now on" and "everyone, full stop" expressible without a
  # sentinel date.
  def covers_join?(joined_at)
    return false if joined_at.blank?
    return false if joined_from.present? && joined_at < joined_from
    return false if joined_until.present? && joined_at > joined_until

    true
  end

  # Human-readable window, or nil when it is open at both ends.
  def join_window
    return nil if joined_from.blank? && joined_until.blank?

    [ joined_from, joined_until ]
  end

  private

  # Level rewards keep `unlock_value` in sync with `level` so a single query
  # shape serves every unlock kind.
  def default_unlock_value
    self.unlock_value = level if unlock_kind == "level" && level.present?
  end

  def claimable_only_for_participation
    errors.add(:claimable, :participation_only) if claimable? && !participation?
  end

  def join_window_is_ordered
    return if joined_from.blank? || joined_until.blank?

    errors.add(:joined_until, :after_start) if joined_until < joined_from
  end
end
