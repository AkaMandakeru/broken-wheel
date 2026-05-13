class StravaToken < ApplicationRecord
  belongs_to :user

  def expired?
    return true if expires_at.nil?
    Time.at(expires_at) < Time.now
  end
end
