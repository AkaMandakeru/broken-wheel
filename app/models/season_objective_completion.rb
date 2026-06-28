class SeasonObjectiveCompletion < ApplicationRecord
  belongs_to :season_participation
  belongs_to :season_objective

  validates :season_objective_id, uniqueness: { scope: :season_participation_id }
end
