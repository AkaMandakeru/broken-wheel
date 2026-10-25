# frozen_string_literal: true

# A signed-in mobile device. Each row is one refresh token; refreshing revokes
# the row and starts the next one in the same family. A revoked token that comes
# back is either a confused client or a stolen token, and the safe answer to
# both is to end the whole family.
#
# The access token is not stored: it is a signed, expiring token for the row
# (generates_token_for), and it stops working the moment the row is revoked
# because revoked_at is part of what it signs.
class ApiSession < ApplicationRecord
  ACCESS_TTL = 15.minutes
  REFRESH_TTL = 60.days
  # Two refreshes with the same token a moment apart are an app racing itself
  # (two requests hitting 401 together), not theft.
  REUSE_GRACE = 30.seconds

  Tokens = Data.define(:session, :access_token, :refresh_token)

  belongs_to :user

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  generates_token_for :access, expires_in: ACCESS_TTL do
    revoked_at
  end

  class << self
    def start!(user, device_name: nil, platform: nil, app_version: nil, family_id: SecureRandom.uuid)
      refresh_token = SecureRandom.base58(48)
      session = create!(
        user: user, family_id: family_id, refresh_token_digest: digest(refresh_token),
        device_name: device_name.to_s.first(100).presence, platform: platform.to_s.first(20).presence,
        app_version: app_version.to_s.first(20).presence,
        expires_at: REFRESH_TTL.from_now, last_used_at: Time.current
      )
      Tokens.new(session: session, access_token: session.generate_token_for(:access), refresh_token: refresh_token)
    end

    def authenticate_access(token)
      return nil if token.blank?

      session = find_by_token_for(:access, token)
      session if session&.usable?
    end

    # The next Tokens for a refresh token, or nil when it is unknown, expired or
    # revoked. Presenting an already-rotated token revokes its family.
    def refresh!(refresh_token, app_version: nil)
      session = find_by(refresh_token_digest: digest(refresh_token))
      return nil unless session

      session.with_lock do
        if session.revoked_at?
          session.revoke_family!(reason: "reuse_detected") if session.reused_after_rotation?
          nil
        elsif session.expires_at.past?
          nil
        else
          session.update!(revoked_at: Time.current, revoked_reason: "rotated")
          start!(session.user, device_name: session.device_name, platform: session.platform,
                               app_version: app_version || session.app_version, family_id: session.family_id)
        end
      end
    end

    def digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def usable? = revoked_at.nil? && expires_at.future?

  def access_token_expires_at = ACCESS_TTL.from_now

  def revoke_family!(reason:)
    self.class.where(family_id: family_id, revoked_at: nil).update_all(revoked_at: Time.current, revoked_reason: reason, updated_at: Time.current)
  end

  def reused_after_rotation?
    revoked_reason == "rotated" && revoked_at < REUSE_GRACE.ago
  end
end
