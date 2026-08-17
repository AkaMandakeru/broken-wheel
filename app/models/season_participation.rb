class SeasonParticipation < ApplicationRecord
  belongs_to :season
  belongs_to :user
  has_many :season_challenge_completions, dependent: :destroy
  has_many :season_objective_completions, dependent: :destroy
  has_many :season_reward_grants, dependent: :destroy

  validates :user_id, uniqueness: { scope: :season_id }

  # Joining a season auto-enrolls the user in every challenge it groups — no
  # manual "join" needed on each season challenge.
  after_create_commit :enroll_in_season_challenges

  scope :by_rank, -> { order(xp: :desc, updated_at: :asc) }
  scope :premium, -> { where(premium: true) }

  MEDAL_TIERS = { "bronze" => 25, "silver" => 60, "gold" => 120, "diamond" => 200 }.freeze

  # 1-based position within the season, computed on read.
  def rank
    season.season_participations.where("xp > ?", xp).count + 1
  end

  def granted_reward_ids
    season_reward_grants.pluck(:season_reward_id)
  end

  # Challenges finished but not yet collected — the XP is set aside until the
  # player claims it.
  def unclaimed_completions
    season_challenge_completions.unclaimed.includes(season_challenge: :challenge).by_completion
  end

  def unclaimed_xp
    season_challenge_completions.unclaimed.sum(:xp_awarded)
  end

  def unclaimed_count
    season_challenge_completions.unclaimed.count
  end

  def level_curve
    season.level_curve_object
  end

  def progress_percent
    level_curve.progress_percent(xp)
  end

  def xp_to_next_level
    level_curve.xp_to_next(xp)
  end

  def max_level?
    level_curve.max_level?(xp)
  end

  # Highest medal tier reached from accumulated challenge fragments.
  def medal_tier
    MEDAL_TIERS.select { |_tier, threshold| medal_fragments >= threshold }.keys.last
  end

  def grant_premium!
    return if premium?

    update!(premium: true, premium_granted_at: Time.current)
    SeasonRewardGranter.new(self).grant_for_level(level)
    SlackNotifier.notify(:premium_granted, user: user, extra: { "Season" => season.name })
  end

  private

  def enroll_in_season_challenges
    season.season_challenges.includes(:challenge).each do |season_challenge|
      ChallengeEnroller.call(user, season_challenge.challenge, season: season)
    end
  end
end
