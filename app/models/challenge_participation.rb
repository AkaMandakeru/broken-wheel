class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user
  # Null for a challenge joined outside any season. Progress is per season, so
  # reusing a challenge in a new season starts everyone from zero there.
  belongs_to :season, optional: true
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :workouts

  before_validation :generate_invite_code, on: :create

  validates :challenge_id, uniqueness: { scope: [ :user_id, :season_id ] }

  scope :standalone, -> { where(season_id: nil) }
  scope :in_season, ->(season) { where(season_id: season) }

  # The participation to show for a challenge in a given context: the season's
  # own row when there is one, otherwise the standalone row.
  scope :for_context, ->(season) { season ? where(season_id: season.id) : where(season_id: nil) }

  def completed?
    completed_at.present?
  end

  def season_challenge
    return nil if season_id.nil?

    @season_challenge ||= SeasonChallenge.find_by(season_id: season_id, challenge_id: challenge_id)
  end

  # Scored over the season's window when season-attached, otherwise the
  # challenge's own dates.
  def window
    season_challenge&.date_window || challenge.workout_window
  end

  # Value recorded for a specific requirement on the last recomputation.
  def progress_for(requirement)
    requirement_progress[requirement.id.to_s]
  end

  # Requirements paired with their current value and percentage, for display.
  def requirement_status
    challenge.challenge_requirements.map do |requirement|
      value = progress_for(requirement)
      {
        requirement: requirement,
        value: value,
        percent: requirement.percent_of(value),
        met: requirement.satisfied_by?(value)
      }
    end
  end

  # Overall completion percentage across every requirement — the average, so a
  # challenge with one finished and one untouched requirement reads 50%.
  def percent_complete
    statuses = requirement_status
    return legacy_percent if statuses.empty?

    (statuses.sum { |s| s[:percent] } / statuses.size.to_f).round
  end

  private

  def legacy_percent
    return 0 unless challenge.target_value.to_f.positive?

    [ ((progress_value.to_f / challenge.target_value.to_f) * 100).round, 100 ].min
  end

  def generate_invite_code
    self.invite_code ||= SecureRandom.hex(8)
  end
end
