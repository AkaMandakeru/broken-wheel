class ClubMembership < ApplicationRecord
  belongs_to :club
  belongs_to :user

  after_create_commit :evaluate_season_objectives

  private

  def evaluate_season_objectives
    SeasonObjectives.enqueue_for(user, kinds: %w[join_club club_workout])
  end
end
