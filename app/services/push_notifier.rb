# frozen_string_literal: true

# Enqueues pushes to the web (Web Push) and to the native apps (Expo). One Web
# Push job per subscription so a single dead endpoint never blocks the rest;
# native devices go in batches, because Expo takes up to 100 messages a request.
class PushNotifier
  def self.notify(user, title:, body:, path: "/", tag: nil)
    enqueue(user.push_subscriptions, user.device_tokens, title:, body:, path:, tag:)
  end

  def self.broadcast(title:, body:, path: "/", tag: nil)
    enqueue(PushSubscription.all, DeviceToken.all, title:, body:, path:, tag:)
  end

  def self.enqueue(subscriptions, device_tokens, title:, body:, path:, tag:)
    payload = { title: title, body: body, path: path, tag: tag }.compact
    subscriptions.find_each do |subscription|
      WebPushDeliveryJob.perform_later(subscription.id, payload)
    end
    device_tokens.in_batches(of: ExpoPushClient::MAX_MESSAGES) do |batch|
      MobilePushDeliveryJob.perform_later(batch.ids, payload)
    end
  end
  private_class_method :enqueue
end
