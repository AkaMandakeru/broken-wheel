# frozen_string_literal: true

# A native app's push token (Expo Push Service). See MobilePushDeliveryJob.
class DeviceToken < ApplicationRecord
  PLATFORMS = %w[expo].freeze
  # Loose on purpose: Expo has changed the prefix before.
  EXPO_TOKEN = /\AExp(?:onent|o)PushToken\[[^\[\]]+\]\z/

  belongs_to :user

  validates :token, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :token, format: { with: EXPO_TOKEN, message: :not_expo_token }, if: -> { platform == "expo" }
  validates :platform, inclusion: { in: PLATFORMS }
  validates :app_version, length: { maximum: 20 }
  validates :locale, length: { maximum: 10 }

  # A token belongs to the device, not the account: when someone signs in with
  # a different account on the same phone, the token moves to that account so
  # the previous one stops receiving its pushes. Returns [device, created?].
  def self.register!(user:, token: nil, platform: nil, app_version: nil, locale: nil)
    device = find_or_initialize_by(token: token)
    created = device.new_record?
    device.update!(user: user, platform: platform, app_version: app_version, locale: locale, last_seen_at: Time.current)
    [ device, created ]
  rescue ActiveRecord::RecordNotUnique
    # Two registrations of a new token raced; the other one inserted it.
    retry
  end
end
