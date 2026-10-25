class SeasonChallenge < ApplicationRecord
  belongs_to :season
  belongs_to :challenge
  has_many :season_challenge_completions, dependent: :destroy

  # Artwork for the reminder email. Lives on the season challenge rather than
  # the challenge because challenges are reused across seasons, and the banner
  # is this season's dressing for the event.
  has_one_attached :email_banner

  # How far ahead of a special event its reminder email goes out.
  REMINDER_LEAD_DAYS = 3

  CATEGORIES = %w[standard daily weekly monthly elite special].freeze

  # Spellings older blueprints still use. "hidden" was what special challenges
  # were called while they stayed off the board until completed.
  LEGACY_CATEGORIES = { "hidden" => "special" }.freeze

  # The category a blueprint value means today.
  def self.canonical_category(value)
    value = value.to_s
    LEGACY_CATEGORIES.fetch(value, value)
  end

  def self.known_category?(value)
    CATEGORIES.include?(canonical_category(value))
  end

  validates :challenge_id, uniqueness: { scope: :season_id }
  validates :category, inclusion: { in: CATEGORIES }
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }
  validates :unlock_level, numericality: { greater_than_or_equal_to: 0 }

  scope :of_category, ->(category) { where(category: category) }
  scope :special, -> { of_category("special") }

  validate :window_within_season
  validate :email_banner_is_a_supported_picture

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

  # True when the challenge covers less of the calendar than the season does,
  # so its dates tell a player something the season header does not. A monthly
  # that spells out the season's own start and end says nothing; a one-day
  # special says everything.
  def narrower_than_season?
    window = date_window
    season_window = season&.date_window
    return false if window.blank? || season_window.blank?

    window.begin > season_window.begin || window.end < season_window.end
  end

  # Was "hidden": a challenge players could only stumble into. They are listed
  # like any other now — the category only marks them as worth more.
  def special?
    category == "special"
  end

  # True once this challenge's window has closed, so the result is final.
  # Measured in the season's own timezone — a week ends when it ends there.
  def window_ended?
    window = date_window
    return false if window.blank?

    season.current_date > window.end
  end

  # The day a special event happens, in the season's own calendar.
  def event_date
    date_window&.begin
  end

  # Due from REMINDER_LEAD_DAYS before the event until the day before it.
  # A window rather than a single day, so a missed scheduler run still sends
  # the next day instead of skipping the event entirely.
  def reminder_due?(today: season.current_date)
    return false unless special? && reminder_sent_at.nil? && event_date

    today >= event_date - REMINDER_LEAD_DAYS && today < event_date
  end

  # The picture the reminder email shows: its own banner, else the challenge's
  # artwork, else the season's. Nil when none of them has one.
  def email_banner_source
    [ email_banner, challenge.image, season.image ].find(&:attached?)
  end

  private

  def email_banner_is_a_supported_picture
    return unless email_banner.attached?

    unless Season::IMAGE_CONTENT_TYPES.include?(email_banner.blob.content_type)
      errors.add(:email_banner, :invalid_type, types: "PNG, JPEG, WEBP, GIF")
    end

    return unless email_banner.blob.byte_size > Season::MAX_IMAGE_BYTES

    errors.add(:email_banner, :too_large, size: "#{Season::MAX_IMAGE_BYTES / 1.megabyte} MB")
  end

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
