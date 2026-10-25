# frozen_string_literal: true

# A registered push device, as the app that registered it sees it.
class DeviceTokenResource < ApplicationResource
  attributes :id, :platform, :token, :app_version, :locale

  attribute(:last_seen_at) { |device| device.last_seen_at&.iso8601 }
  attribute(:created_at) { |device| device.created_at.iso8601 }
end
