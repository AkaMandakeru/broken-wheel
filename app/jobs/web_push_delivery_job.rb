# frozen_string_literal: true

class WebPushDeliveryJob < ApplicationJob
  queue_as :default

  def perform(subscription_id, payload)
    subscription = PushSubscription.find_by(id: subscription_id)
    return unless subscription

    config = Rails.application.config.x.web_push
    return if config[:public_key].blank? || config[:private_key].blank?

    WebPush.payload_send(
      message: payload.to_json,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh_key,
      auth: subscription.auth_key,
      vapid: {
        subject: config[:subject],
        public_key: config[:public_key],
        private_key: config[:private_key]
      },
      urgency: "normal"
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    # Endpoint is gone (404/410) — drop it so we stop trying.
    subscription&.destroy
  rescue WebPush::ResponseError => e
    Rails.logger.warn("WebPush delivery failed for subscription=#{subscription_id}: #{e.message}")
  end
end
