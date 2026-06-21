class User < ApplicationRecord
  has_one_attached :avatar
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

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :timeoutable

  validates :first_name, :last_name, presence: true
  # The displayed title (singular) must be one the user has actually earned.
  validate :displayed_title_is_earned

  after_create :grant_default_titles

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

  private

  def grant_default_titles
    defaults = Titles.defaults.map(&:to_s)
    return if defaults.empty?

    update_column(:titles, (Array(self[:titles]).map(&:to_s) | defaults))
  end

  def displayed_title_is_earned
    return if title.blank?

    errors.add(:title, :inclusion) unless titles.include?(title.to_sym)
  end
end
