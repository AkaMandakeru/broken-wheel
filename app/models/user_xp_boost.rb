# frozen_string_literal: true

# A temporary XP multiplier. Because season XP is recomputed from scratch, a
# boost is applied per workout by that workout's date rather than as a global
# multiplier on the total — otherwise an expired boost would keep paying out,
# or a new one would retroactively inflate the whole season.
class UserXpBoost < ApplicationRecord
  belongs_to :user

  validates :multiplier, numericality: { greater_than: 0 }
  validates :source_key, presence: true, uniqueness: { scope: :user_id }
  validate :ends_after_starts

  scope :active_at, ->(time) { where(starts_at: ..time).where(ends_at: time..) }

  def covers?(time)
    return false if time.blank?

    time = time.to_time if time.is_a?(Date)
    starts_at <= time && ends_at >= time
  end

  # A boost covers a calendar day if it overlaps that day at all.
  def covers_date?(date)
    return false if date.blank?

    starts_at.to_date <= date && ends_at.to_date >= date
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) if ends_at <= starts_at
  end
end
