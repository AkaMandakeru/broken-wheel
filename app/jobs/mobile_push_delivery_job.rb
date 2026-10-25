# frozen_string_literal: true

# Sends one push to a batch of native devices through Expo (at most
# ExpoPushClient::MAX_MESSAGES per job, as PushNotifier slices them).
#
# The payload is the same `title/body/path/tag` Web Push gets; the app routes
# `path` itself. Expo has no collapse key, so `tag` only travels in `data`.
class MobilePushDeliveryJob < ApplicationJob
  queue_as :default

  RECEIPT_DELAY = 15.minutes

  retry_on ExpoPushClient::Unavailable, wait: :polynomially_longer, attempts: 5 do |_job, error|
    Rails.logger.warn("Mobile push gave up: #{error.message}")
  end
  discard_on ExpoPushClient::Error do |_job, error|
    Rails.logger.warn("Mobile push rejected: #{error.message}")
  end

  def perform(device_token_ids, payload)
    devices = DeviceToken.where(id: device_token_ids).order(:id).to_a
    return if devices.empty?

    payload = payload.symbolize_keys
    tickets = ExpoPushClient.new.send_messages(devices.map { |device| message_for(device, payload) })

    receipt_devices = {}
    devices.zip(tickets).each do |device, ticket|
      next unless ticket

      if ticket["status"] == "ok"
        receipt_devices[ticket["id"]] = device.id
      elsif ticket.dig("details", "error") == "DeviceNotRegistered"
        # The app was uninstalled or the token was revoked — like a 410 on the web.
        device.delete
      else
        Rails.logger.warn("Mobile push failed for device_token=#{device.id}: #{ticket["message"]}")
      end
    end

    ExpoPushReceiptsJob.set(wait: RECEIPT_DELAY).perform_later(receipt_devices) if receipt_devices.any?
  end

  private

  def message_for(device, payload)
    {
      to: device.token,
      title: payload[:title],
      body: payload[:body],
      data: { path: payload[:path], tag: payload[:tag] }.compact,
      sound: "default"
    }.compact
  end
end
