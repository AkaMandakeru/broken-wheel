# frozen_string_literal: true

class StravaToken < ApplicationRecord
  EXPIRY_LEEWAY = 60.seconds

  belongs_to :user

  encrypts :access_token
  encrypts :refresh_token

  validates :refresh_token, presence: true

  def expired?
    return true if expires_at.blank?

    Time.zone.at(expires_at) <= Time.current + EXPIRY_LEEWAY
  end

  def expires_at_time
    return nil if expires_at.blank?

    Time.zone.at(expires_at)
  end
end
