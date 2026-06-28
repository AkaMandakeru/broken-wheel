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

  # 1-based position within the season, computed on read.
  def rank
    season.season_participations.where("xp > ?", xp).count + 1
  end

  def granted_reward_ids
    season_reward_grants.pluck(:season_reward_id)
  end

  private

  def enroll_in_season_challenges
    season.season_challenges.includes(:challenge).each do |season_challenge|
      ChallengeEnroller.call(user, season_challenge.challenge)
    end
  end
end
