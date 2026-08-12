class Challenge < ApplicationRecord
  has_one_attached :image

  has_many :challenge_participations
  has_many :participants, through: :challenge_participations, source: :user
  has_many :timeline_posts
  has_many :challenge_requirements, -> { ordered }, dependent: :destroy
  has_many :season_challenges, dependent: :destroy

  accepts_nested_attributes_for :challenge_requirements, allow_destroy: true

  # Must stay in sync with Strava::ActivityImporter::SPORT_MAP — a sport the
  # importer can produce but a challenge can't reference is silently unmatchable.
  SPORTS = %w[run bike soccer].freeze
  CHALLENGE_TYPES = %w[weekly biweekly monthly annually custom specific_day].freeze
  TARGET_UNITS = %w[km hours times].freeze
  STATUSES = %w[active completed].freeze

  validates :title, presence: true
  validates :challenge_type, inclusion: { in: CHALLENGE_TYPES }, allow_blank: true
  validates :sport, inclusion: { in: SPORTS }, allow_blank: true
  validates :target_unit, inclusion: { in: TARGET_UNITS }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :target_value, numericality: { greater_than: 0 }, allow_nil: true
  validate :ends_after_starts

  scope :of_type, ->(type) { where(challenge_type: type) if type.present? && CHALLENGE_TYPES.include?(type) }

  def self.current_week_window(today: Date.current)
    today.beginning_of_week(:sunday)..today.end_of_week(:sunday)
  end

  # Date range used to back-fill existing workouts when a user joins.
  # weekly/monthly track the current period; other types use the challenge's
  # own start/end dates. Returns nil when no window can be determined.
  def workout_window(today: Date.current)
    case challenge_type
    when "weekly"  then self.class.current_week_window(today: today)
    when "monthly" then today.beginning_of_month..today.end_of_month
    when "specific_day"
      # Completed by doing the activity on the configured day (starts_at).
      starts_at ? (starts_at.to_date..starts_at.to_date) : nil
    else
      starts_at && ends_at ? (starts_at.to_date..ends_at.to_date) : nil
    end
  end

  # Default (system) challenges carry a stable `key` and are translated via
  # locale files. Challenges created by an admin/customer have no key and show
  # the title/description provided by their creator.
  def default?
    key.present?
  end

  # The headline requirement, used wherever a single number stands in for the
  # whole challenge (cards, progress bars, the legacy target_value column).
  def primary_requirement
    challenge_requirements.first
  end

  def multi_requirement?
    challenge_requirements.size > 1
  end

  def display_title
    default? ? I18n.t("challenges.defaults.#{key}.title", default: title.to_s) : title
  end

  def display_description
    default? ? I18n.t("challenges.defaults.#{key}.description", default: description.to_s) : description
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, :after_start) if ends_at < starts_at
  end
end
