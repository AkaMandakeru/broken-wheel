class User < ApplicationRecord
  # Named variants are generated right after upload (preprocessed), so the
  # first person to see a picture never waits on libvips. Served through the
  # CDN by the `cdn_image` route — see ImageUrls.
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 160, 160 ], preprocessed: true
    attachable.variant :medium, resize_to_limit: [ 512, 512 ], preprocessed: true
  end
  has_one :strava_token, dependent: :destroy

  has_many :challenge_participations
  has_many :event_participations
  has_many :events, through: :event_participations
  has_many :workouts
  has_many :user_badges
  has_many :badges, through: :user_badges
  has_many :club_memberships
  has_many :clubs, through: :club_memberships
  has_many :support_tickets, dependent: :destroy
  has_many :support_messages, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :season_participations, dependent: :destroy
  has_many :seasons, through: :season_participations
  has_many :season_activities, dependent: :destroy
  has_many :timeline_posts, dependent: :destroy
  has_many :daily_challenge_assignments, dependent: :destroy
  has_many :coin_transactions, dependent: :destroy
  has_many :user_cosmetics, dependent: :destroy
  has_many :cosmetics, through: :user_cosmetics
  has_many :user_xp_boosts, dependent: :destroy
  # Mobile API
  has_many :api_sessions, dependent: :delete_all
  has_many :device_tokens, dependent: :delete_all
  has_many :idempotency_keys, dependent: :delete_all
  has_many :content_reports, foreign_key: :reporter_id, dependent: :delete_all, inverse_of: :reporter
  has_many :user_blocks, foreign_key: :blocker_id, dependent: :delete_all, inverse_of: :blocker
  has_many :blocked_users, through: :user_blocks, source: :blocked

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable

  # What a player may change about themselves, from the profile form or the
  # app (PATCH /api/v1/me). `avatar` and `sports` are permitted beside these —
  # the form uploads a file and the app sends a signed id.
  PROFILE_ATTRIBUTES = %i[first_name last_name title nickname document phone blood_type address email_reminders].freeze
  SPORTS = Challenge::SPORTS

  validates :first_name, :last_name, presence: true
  validate :sports_are_known, if: :sports_changed?
  # The displayed title (singular) must be one the user has actually earned.
  validate :displayed_title_is_earned

  after_create :grant_default_titles
  # A new password signs every mobile device out, wherever it was changed.
  after_update_commit :revoke_api_sessions, if: :saved_change_to_encrypted_password?

  def connected_to_strava?
    strava_token.present? && strava_token.refresh_token.present?
  end

  # --- Earned titles (catalogue lives in config/titles.yml) ------------------

  # Earned title keys as symbols, e.g. [:rookie, :daily_runner].
  def titles
    Array(self[:titles]).map(&:to_sym)
  end

  # Grant a title from the catalogue. Returns false for unknown keys.
  #   user.add_title(:slacker)
  def add_title(key)
    return false unless Titles.exists?(key)

    stored = Array(self[:titles]).map(&:to_s)
    unless stored.include?(key.to_s)
      self[:titles] = stored + [ key.to_s ]
      save
    end
    true
  end

  def remove_title(key)
    self[:titles] = Array(self[:titles]).map(&:to_s) - [ key.to_s ]
    self.title = nil if title == key.to_s
    save
  end

  def title?(key)
    titles.include?(key.to_sym)
  end

  # Titles the user may pick as their displayed title (the ones they've earned).
  def available_titles
    titles
  end

  # Localized label for the displayed title, or nil when none is set.
  def title_label
    title.present? ? Titles.label(title) : nil
  end

  # --- Season history --------------------------------------------------------

  # Every season the user took part in, newest first, with the artwork the medal
  # shelf renders. Loaded whole rather than paginated: a player accumulates one
  # row per season, so this stays a handful of records for years.
  def season_history
    season_participations.joins(:season)
                         .includes(season: { image_attachment: :blob })
                         .merge(Season.by_recent)
  end

  # Seasons finished with a medal. Participations below bronze still belong in
  # the history — they just have nothing to hang on the shelf.
  def season_medals
    season_history.select(&:medal_tier)
  end

  # --- Unlockable cosmetic themes (granted by season rewards) ----------------

  def unlocked_themes
    Array(self[:unlocked_themes]).map(&:to_s)
  end

  def unlock_theme(key)
    return false if key.blank?

    stored = unlocked_themes
    update_column(:unlocked_themes, stored + [ key.to_s ]) unless stored.include?(key.to_s)
    true
  end

  # --- Season announcements --------------------------------------------------

  # Which "new season" banners this user has already dismissed. Kept in the
  # preferences jsonb rather than its own table — it is a UI preference, and
  # there is exactly one row per user either way.
  DISMISSED_ANNOUNCEMENTS_KEY = "dismissed_season_announcements"

  def dismissed_season_announcements
    Array(preferences_hash[DISMISSED_ANNOUNCEMENTS_KEY]).map(&:to_i)
  end

  def dismiss_season_announcement(season_id)
    ids = (dismissed_season_announcements + [ season_id.to_i ]).uniq.last(20)
    update_column(:preferences, preferences_hash.merge(DISMISSED_ANNOUNCEMENTS_KEY => ids))
  end

  def dismissed_season_announcement?(season_id)
    dismissed_season_announcements.include?(season_id.to_i)
  end

  # --- Engagement emails -----------------------------------------------------

  # Reminders and other non-transactional email. Account email (password reset,
  # lockout) is never covered by this — those are sent regardless.
  EMAIL_OPT_OUT_KEY = "email_reminders_opt_out"
  # The locale the user last browsed in. Emails are sent from a job with no
  # request to detect a locale from, so it is remembered here.
  LOCALE_KEY = "locale"

  # Bots live under a reserved domain no provider will deliver to.
  scope :reachable_by_email, -> {
    where("COALESCE((preferences ->> :key)::boolean, false) = false", key: EMAIL_OPT_OUT_KEY)
      .where.not("email LIKE ?", "%@#{SeasonSandbox::BOT_EMAIL_DOMAIN}")
  }

  # Unsubscribe links must work without signing in and must never expire — a
  # link from an old email that fails is how people end up marking us as spam.
  generates_token_for :email_unsubscribe

  def email_reminders?
    !ActiveModel::Type::Boolean.new.cast(preferences_hash[EMAIL_OPT_OUT_KEY])
  end
  alias_method :email_reminders, :email_reminders?

  # Lets the profile form submit a plain checkbox.
  def email_reminders=(value)
    self[:preferences] = preferences_hash.merge(EMAIL_OPT_OUT_KEY => !ActiveModel::Type::Boolean.new.cast(value))
  end

  def unsubscribe_from_emails!
    update_column(:preferences, preferences_hash.merge(EMAIL_OPT_OUT_KEY => true))
  end

  def resubscribe_to_emails!
    update_column(:preferences, preferences_hash.merge(EMAIL_OPT_OUT_KEY => false))
  end

  def email_locale
    stored = preferences_hash[LOCALE_KEY].to_s
    return stored.to_sym if I18n.available_locales.map(&:to_s).include?(stored)

    ENV.fetch("MAILER_DEFAULT_LOCALE", I18n.default_locale).to_sym
  end

  def remember_locale(locale)
    return if preferences_hash[LOCALE_KEY] == locale.to_s

    update_column(:preferences, preferences_hash.merge(LOCALE_KEY => locale.to_s))
  end

  # --- Cosmetics -------------------------------------------------------------

  # Everyone wearing this cosmetic in this slot. equipped_cosmetics is jsonb, so
  # this scope is the one place that has to know the column's shape.
  scope :wearing, ->(kind, key) {
    where("equipped_cosmetics ->> :kind = :key", kind: kind.to_s, key: key.to_s)
  }

  # { "frame" => "legendary_frame", "name_color" => "gold", ... }
  def equipped
    (self[:equipped_cosmetics] || {}).with_indifferent_access
  end

  def equipped_cosmetic(kind)
    key = equipped[kind.to_s]
    return nil if key.blank?

    # Eager-loads the blob: every caller renders the artwork straight away.
    cosmetics.with_artwork.find_by(key: key, kind: kind.to_s)
  end

  def equipped_banner
    equipped_cosmetic("banner")
  end

  def equipped_frame
    equipped_cosmetic("frame")
  end

  # One kind of the collection, in catalogue order. Unrenderable rows are left
  # out because equip_cosmetic! would refuse them anyway.
  def owned_cosmetics(kind)
    cosmetics.of_kind(kind.to_s).renderable.ordered.with_artwork
  end

  # The rest of the catalogue for that kind — what the locker shows as locked.
  def unowned_cosmetics(kind)
    owned = user_cosmetics.select(:cosmetic_id)
    Cosmetic.of_kind(kind.to_s).renderable.where.not(id: owned).ordered.with_artwork
  end

  # Equipping is restricted to cosmetics the user owns and that we can actually
  # render — an unrenderable item stays in the collection until its art lands.
  def equip_cosmetic!(kind, key)
    cosmetic = cosmetics.find_by(key: key, kind: kind.to_s)
    return false if cosmetic.nil? || !cosmetic.renderable?

    update!(equipped_cosmetics: equipped.merge(kind.to_s => key.to_s))
    true
  end

  def unequip_cosmetic!(kind)
    update!(equipped_cosmetics: equipped.except(kind.to_s))
  end

  def owns_cosmetic?(key)
    cosmetics.exists?(key: key.to_s)
  end

  # Multiplier in force at a given moment, from any active XP boost.
  def xp_multiplier_at(time)
    user_xp_boosts.select { |boost| boost.covers?(time) }.map(&:multiplier).max&.to_f || 1.0
  end

  private

  def preferences_hash
    (self[:preferences] || {}).with_indifferent_access
  end

  def revoke_api_sessions
    api_sessions.active.update_all(revoked_at: Time.current, revoked_reason: "password_changed", updated_at: Time.current)
  end

  def grant_default_titles
    defaults = Titles.defaults.map(&:to_s)
    return if defaults.empty?

    update_column(:titles, (Array(self[:titles]).map(&:to_s) | defaults))
  end

  def sports_are_known
    errors.add(:sports, :inclusion) if (Array(sports) - SPORTS).any?
  end

  def displayed_title_is_earned
    return if title.blank?

    errors.add(:title, :inclusion) unless titles.include?(title.to_sym)
  end
end
