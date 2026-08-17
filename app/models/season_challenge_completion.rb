class SeasonChallengeCompletion < ApplicationRecord
  belongs_to :season_participation
  belongs_to :season_challenge

  validates :season_challenge_id, uniqueness: { scope: :season_participation_id }

  scope :claimed, -> { where.not(claimed_at: nil) }
  scope :unclaimed, -> { where(claimed_at: nil) }
  scope :by_completion, -> { order(completed_at: :desc) }

  def claimed?
    claimed_at.present?
  end

  # Stamps the claim and returns whether this call is the one that did it, so a
  # double-click or a replayed request can't pay the XP twice.
  def claim!
    return false if claimed?

    updated = self.class.where(id: id, claimed_at: nil).update_all(claimed_at: Time.current, updated_at: Time.current)
    return false unless updated.positive?

    reload
    true
  end
end
