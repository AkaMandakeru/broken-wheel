class Challenge < ApplicationRecord
  has_one_attached :image

  has_many :challenge_participations
  has_many :participants, through: :challenge_participations, source: :user
  has_many :timeline_posts

  SPORTS = %w[run bike soccer].freeze
  CHALLENGE_TYPES = %w[weekly monthly].freeze
  TARGET_UNITS = %w[km hours times].freeze
  STATUSES = %w[active completed].freeze

  validates :title, presence: true
  validates :challenge_type, inclusion: { in: CHALLENGE_TYPES }, allow_blank: true
  validates :sport, inclusion: { in: SPORTS }, allow_blank: true
  validates :target_unit, inclusion: { in: TARGET_UNITS }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :target_value, numericality: { greater_than: 0 }, allow_nil: true
  validate :ends_after_starts

  def self.current_week_window(today: Date.current)
    today.beginning_of_week(:sunday)..today.end_of_week(:sunday)
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, :after_start) if ends_at < starts_at
  end
end
