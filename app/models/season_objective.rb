class SeasonObjective < ApplicationRecord
  belongs_to :season
  has_many :season_objective_completions, dependent: :destroy

  # Action-based season goals that aren't workout challenges. `kind` survives
  # for the two original club goals and for icon/grouping; progress itself now
  # resolves through ChallengeMetrics like every other mechanic.
  KINDS  = %w[join_club club_workout legacy custom].freeze
  TRACKS = %w[standard legacy].freeze

  # The five values of the Legacy Missions progression.
  LEGACY_KEYS = %w[discipline courage resilience strength legacy].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :track, inclusion: { in: TRACKS }
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }
  validates :target, numericality: { greater_than: 0 }
  validates :metric, inclusion: { in: ->(_o) { ChallengeMetrics.keys } }, allow_blank: true

  scope :standard, -> { where(track: "standard") }
  scope :legacy, -> { where(track: "legacy") }

  before_validation :default_metric

  def legacy?
    track == "legacy"
  end

  def metric_key
    metric.presence || default_metric_for_kind
  end

  def display_name
    return name if name.present?

    I18n.t("seasons.objectives.kinds.#{kind}", default: kind.to_s.humanize)
  end

  def display_description
    I18n.t(
      "seasons.objectives.descriptions.#{kind}",
      count: target,
      default: I18n.t("challenges.requirements.#{metric_key}", count: target, target: target, unit: "", default: "")
    )
  end

  private

  def default_metric
    self.metric = default_metric_for_kind if metric.blank?
  end

  def default_metric_for_kind
    case kind
    when "join_club"    then "club_member"
    when "club_workout" then "club_workout_count"
    else "activity_count"
    end
  end
end
