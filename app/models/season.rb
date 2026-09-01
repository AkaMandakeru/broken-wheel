class Season < ApplicationRecord
  has_one_attached :image

  has_many :season_challenges, -> { order(:position) }, dependent: :destroy
  has_many :challenges, through: :season_challenges
  has_many :season_objectives, -> { order(:position) }, dependent: :destroy
  has_many :season_participations, dependent: :destroy
  # Season-scoped challenge progress belongs to the season; without this a
  # season could not be deleted once anyone had taken part in its challenges.
  has_many :challenge_participations, dependent: :destroy
  has_many :season_rewards, -> { order(:level) }, dependent: :destroy
  has_many :season_activities, dependent: :destroy
  has_many :season_community_goals, dependent: :destroy
  has_many :daily_challenge_templates, dependent: :destroy
  has_many :daily_challenge_assignments, dependent: :destroy
  has_many :events, dependent: :nullify

  STATUSES = %w[upcoming active ended].freeze
  THEMES   = %w[default summer winter spring autumn legacy].freeze

  MAX_SUPPORTED_LEVEL = 100

  # How many finished seasons stay reachable behind the current one.
  ARCHIVE_DEPTH = 1

  # The picture is rendered on the public season page, so what can be uploaded
  # is constrained here rather than discovered at render time.
  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_IMAGE_BYTES = 5.megabytes

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :theme, inclusion: { in: THEMES }, allow_blank: true
  validates :xp_multiplier, numericality: { greater_than: 0 }
  validates :max_level, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SUPPORTED_LEVEL
  }
  validates :top_level_xp, numericality: { greater_than: 0 }, allow_nil: true
  validates :curve_exponent, numericality: { greater_than: 0 }
  validates :key, uniqueness: true, allow_blank: true
  validate :time_zone_is_known
  before_validation :normalize_time_zone
  validate :image_is_a_supported_picture

  # Clearing an optional curve field in the form submits "", which casts to nil.
  # `curve_exponent` is NOT NULL with a sensible default, so a blank field should
  # mean "use the default" rather than failing validation on a value the operator
  # never deliberately set.
  before_validation :restore_default_curve_exponent

  # The stored curve is derived, so it must be rebuilt whenever the inputs move —
  # otherwise changing max_level in the admin form would silently do nothing,
  # because the curve's own length is what defines the season's level count.
  before_save :rebuild_level_curve, if: :level_curve_stale?

  scope :active, -> { where(status: "active") }
  scope :ended, -> { where(status: "ended") }
  scope :by_recent, -> { order(starts_at: :desc) }

  # Players may look back exactly one season. Older ones close for good: a
  # season nobody can still affect is a dead leaderboard, and leaving it open
  # invites people to measure themselves against a board they can never enter.
  scope :recent_archive, -> { ended.by_recent.limit(ARCHIVE_DEPTH) }

  # Everything a player may open — the current season, anything not yet started,
  # and that one season of history. Admins bypass this via the admin panel.
  scope :browsable, -> {
    where(status: %w[upcoming active]).or(where(id: recent_archive.select(:id)))
  }

  after_update_commit :finalize_if_ended

  # One registration covering both cases on purpose: Rails dedupes callbacks by
  # filter name, so a separate after_create_commit :announce_if_started would
  # silently *replace* the update one — and activating an existing season, the
  # normal path, would never announce.
  after_commit :announce_if_started, on: [ :create, :update ]

  def active?
    status == "active"
  end

  def ended?
    status == "ended"
  end

  def window
    (starts_at..ends_at) if starts_at && ends_at
  end

  def date_window
    (starts_at.to_date..ends_at.to_date) if starts_at && ends_at
  end

  def level_curve_object
    @level_curve_object ||= Seasons::LevelCurve.for(self)
  end

  def battle_pass?
    max_level > Leveling::MAX_LEVEL
  end

  def effective_top_level_xp
    top_level_xp.presence || Seasons::LevelCurve::DEFAULT_TOP_LEVEL_XP
  end

  # Rewards and elite gates pinned above the current level ceiling can never be
  # reached. Shrinking a season's level count is exactly when this happens, so
  # the admin screen surfaces it instead of letting content go quietly dead.
  def unreachable_rewards
    season_rewards.where(unlock_kind: "level").where(level: (max_level + 1)..)
  end

  def unreachable_challenges
    season_challenges.where(unlock_level: (max_level + 1)..)
  end

  def level_config_warnings
    warnings = []
    warnings << { kind: :rewards, records: unreachable_rewards.to_a } if unreachable_rewards.exists?
    warnings << { kind: :challenges, records: unreachable_challenges.to_a } if unreachable_challenges.exists?
    warnings
  end

  def zone
    ActiveSupport::TimeZone[time_zone] || Time.zone
  end

  # "Today" for dailies and hour-based challenges, in the season's own timezone.
  def current_date
    Time.current.in_time_zone(zone).to_date
  end

  # Days the season has been running, clamped to its own window.
  def elapsed_days(today: current_date)
    return 0 unless starts_at

    last = [ today, ends_at&.to_date ].compact.min
    [ (last - starts_at.to_date).to_i + 1, 0 ].max
  end

  def weekly_challenges
    season_challenges.where(category: "weekly")
  end

  private

  def restore_default_curve_exponent
    self.curve_exponent = Seasons::LevelCurve::DEFAULT_EXPONENT if curve_exponent.blank?
  end

  def level_curve_stale?
    return true if level_curve.blank? || new_record?

    will_save_change_to_max_level? || will_save_change_to_top_level_xp? ||
      will_save_change_to_curve_exponent? || Array(level_curve).size != max_level
  end

  def rebuild_level_curve
    self.level_curve = Seasons::LevelCurve.build(
      max_level, top_xp: effective_top_level_xp, exponent: curve_exponent
    )
    @level_curve_object = nil
  end

  def time_zone_is_known
    return if time_zone.blank? || ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, :invalid)
  end

  # Store the IANA identifier ("America/Sao_Paulo"), never a Rails display name
  # ("Brasilia"). Rails' time_zone_select submits display names, and a stored
  # display name that no longer matches an option makes the browser fall back to
  # the first entry in the list — which silently moved every season to UTC-12.
  def normalize_time_zone
    return if time_zone.blank?

    zone = ActiveSupport::TimeZone[time_zone]
    self.time_zone = zone.tzinfo.name if zone
  end

  def image_is_a_supported_picture
    return unless image.attached?

    unless IMAGE_CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:image, :invalid_type, types: "PNG, JPEG, WEBP, GIF")
    end

    return unless image.blob.byte_size > MAX_IMAGE_BYTES

    errors.add(:image, :too_large, size: "#{MAX_IMAGE_BYTES / 1.megabyte} MB")
  end

  # A season opening is worth telling people about, but only the first time it
  # opens — announcing is stamped on the record, so flipping status back and
  # forth doesn't notify everyone again.
  def announce_if_started
    return unless active?
    return if announced_at.present?
    return unless previously_new_record? || saved_change_to_status?

    AnnounceSeasonJob.perform_later(id)
  end

  # End-of-season payouts run once, the moment a season is closed.
  def finalize_if_ended
    return unless saved_change_to_status? && ended?
    return if finalized_at.present?

    SeasonFinalizeJob.perform_later(id)
  end
end
