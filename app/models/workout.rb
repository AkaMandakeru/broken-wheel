class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :challenge_participation, optional: true
end
