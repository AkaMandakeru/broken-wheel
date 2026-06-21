# frozen_string_literal: true

# Enqueues Web Push deliveries. One background job per subscription so a single
# dead endpoint never blocks the rest.
class PushNotifier
  def self.notify(user, title:, body:, path: "/", tag: nil)
    enqueue(user.push_subscriptions, title:, body:, path:, tag:)
  end

  def self.broadcast(title:, body:, path: "/", tag: nil)
    enqueue(PushSubscription.all, title:, body:, path:, tag:)
  end

  def self.enqueue(subscriptions, title:, body:, path:, tag:)
    payload = { title: title, body: body, path: path, tag: tag }.compact
    subscriptions.find_each do |subscription|
      WebPushDeliveryJob.perform_later(subscription.id, payload)
    end
  end
end
