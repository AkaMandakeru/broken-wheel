# frozen_string_literal: true

# A player hiding another player's content from themselves. One-way: the
# blocked player still sees the blocker's posts.
class UserBlock < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: { scope: :blocker_id }
  validate :not_self

  # A subquery of the ids `user` has blocked, for `where.not(user_id: …)`.
  def self.blocked_ids_by(user)
    where(blocker_id: user.id).select(:blocked_id)
  end

  # Blocking twice is a no-op, including when two taps race.
  def self.block!(blocker, blocked)
    find_or_create_by!(blocker: blocker, blocked: blocked)
  rescue ActiveRecord::RecordNotUnique
    find_by!(blocker: blocker, blocked: blocked)
  end

  private

  def not_self
    errors.add(:blocked_id, :invalid) if blocker_id == blocked_id
  end
end
