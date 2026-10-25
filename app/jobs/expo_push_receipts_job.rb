# frozen_string_literal: true

# Checks the receipts of a MobilePushDeliveryJob batch. Expo usually reports a
# device that is gone (DeviceNotRegistered) here rather than in the ticket.
# Receipts don't name the token, so the job carries { receipt_id => device_token_id }.
class ExpoPushReceiptsJob < ApplicationJob
  queue_as :default

  retry_on ExpoPushClient::Unavailable, wait: :polynomially_longer, attempts: 5 do |_job, error|
    Rails.logger.warn("Expo receipts gave up: #{error.message}")
  end
  discard_on ExpoPushClient::Error do |_job, error|
    Rails.logger.warn("Expo receipts rejected: #{error.message}")
  end

  def perform(receipt_devices)
    receipt_devices.keys.each_slice(ExpoPushClient::MAX_RECEIPT_IDS) do |ids|
      gone = ExpoPushClient.new.receipts(ids).filter_map do |id, receipt|
        receipt_devices[id] if receipt["status"] == "error" && receipt.dig("details", "error") == "DeviceNotRegistered"
      end
      DeviceToken.where(id: gone).delete_all if gone.any?
    end
  end
end
