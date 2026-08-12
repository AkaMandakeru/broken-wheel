# frozen_string_literal: true

class UserCosmetic < ApplicationRecord
  belongs_to :user
  belongs_to :cosmetic

  validates :cosmetic_id, uniqueness: { scope: :user_id }

  before_validation { self.unlocked_at ||= Time.current }

  scope :recent, -> { order(unlocked_at: :desc) }
end
