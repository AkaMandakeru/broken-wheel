# frozen_string_literal: true

# What is left of the badge catalogue after achievements moved to seasons.
#
# Badges are no longer a progression of their own — nothing computes them from
# workout history any more. The only ones still minted are handed out by
# something else that already decided they were earned: a season reward
# (SeasonRewardGranter) or finishing a challenge (RecomputeChallengeProgress).
# The medals a player collects season by season live on SeasonParticipation,
# not here.
class Badge < ApplicationRecord
  has_many :user_badges
  has_many :users, through: :user_badges

  CATEGORIES = {
    "season"               => "Season Rewards",
    "challenge_completion" => "Challenge Completions"
  }.freeze

  scope :season,               -> { where(badge_type: "season") }
  scope :challenge_completion, -> { where(badge_type: "challenge_completion") }

  # Both remaining sources write their own display text at grant time — the
  # season blueprint's reward name, or the challenge's title — so there is
  # nothing left to derive from thresholds.
  def display_name
    name
  end

  def display_title
    title
  end

  def display_description
    description
  end
end
