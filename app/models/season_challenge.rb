class SeasonChallenge < ApplicationRecord
  belongs_to :season
  belongs_to :challenge
  has_many :season_challenge_completions, dependent: :destroy

  CATEGORIES = %w[standard daily weekly monthly elite hidden].freeze

  validates :challenge_id, uniqueness: { scope: :season_id }
  validates :category, inclusion: { in: CATEGORIES }
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }
  validates :unlock_level, numericality: { greater_than_or_equal_to: 0 }

  scope :of_category, ->(category) { where(category: category) }
  scope :visible, -> { where(hidden: false) }
  scope :secret, -> { where(hidden: true) }

  validate :window_within_season

  # The dates this challenge is scored over *in this season*. Blank means the
  # whole season, which is what lets the same challenge be reused in a later
  # season and measure that season instead of the one it was written for.
  def date_window
    return (starts_at.to_date..ends_at.to_date) if starts_at && ends_at

    season.date_window
  end

  # When a challenge is added to a season, enroll everyone already in the season.
  after_create_commit :enroll_existing_participants

  def locked_for?(participation)
    unlock_level.positive? && participation&.level.to_i < unlock_level
  end

  def elite?
    category == "elite"
  end

  private

  def enroll_existing_participants
    EnrollSeasonParticipantsJob.perform_later(id)
  end

  # An explicit window outside the season would score nothing — usually a sign
  # the dates were copied from the season this challenge came from.
  def window_within_season
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) if ends_at < starts_at

    season_window = season&.date_window
    return if season_window.blank?

    unless season_window.cover?(starts_at.to_date) && season_window.cover?(ends_at.to_date)
      errors.add(:starts_at, :outside_season)
    end
  end
end
