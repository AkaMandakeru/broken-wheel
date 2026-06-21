class Season < ApplicationRecord
  has_one_attached :image

  has_many :season_challenges, -> { order(:position) }, dependent: :destroy
  has_many :challenges, through: :season_challenges
  has_many :season_participations, dependent: :destroy
  has_many :season_rewards, -> { order(:level) }, dependent: :destroy
  has_many :season_activities, dependent: :destroy
  has_many :events, dependent: :nullify

  STATUSES = %w[upcoming active ended].freeze
  THEMES   = %w[default summer winter spring autumn].freeze

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :theme, inclusion: { in: THEMES }, allow_blank: true
  validates :xp_multiplier, numericality: { greater_than: 0 }
  validates :key, uniqueness: true, allow_blank: true

  scope :active, -> { where(status: "active") }
  scope :by_recent, -> { order(starts_at: :desc) }

  def active?
    status == "active"
  end

  def ended?
    status == "ended"
  end

  def window
    (starts_at..ends_at) if starts_at && ends_at
  end
end
