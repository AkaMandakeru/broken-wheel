# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushNotifier do
  include ActiveJob::TestHelper

  let(:user) { build_user }

  def subscribe(user)
    user.push_subscriptions.create!(endpoint: "https://push.example/#{SecureRandom.hex(4)}", p256dh_key: "p", auth_key: "a")
  end

  def register_device(user)
    DeviceToken.create!(user: user, platform: "expo", token: "ExponentPushToken[#{SecureRandom.hex(8)}]")
  end

  describe ".notify" do
    it "sends to the user's browsers one by one and to their phones in one batch" do
      subscription = subscribe(user)
      devices = Array.new(2) { register_device(user) }
      register_device(build_user)

      PushNotifier.notify(user, title: "Level up", body: "Level 3", path: "/seasons/1", tag: "level")

      payload = { title: "Level up", body: "Level 3", path: "/seasons/1", tag: "level" }
      expect(WebPushDeliveryJob).to have_been_enqueued.once.with(subscription.id, payload)
      expect(MobilePushDeliveryJob).to have_been_enqueued.once.with(match_array(devices.map(&:id)), payload)
    end

    it "enqueues no mobile job for a user without devices" do
      PushNotifier.notify(user, title: "Hi", body: "There")

      expect(MobilePushDeliveryJob).not_to have_been_enqueued
    end
  end

  describe ".broadcast" do
    it "splits the devices into batches Expo accepts" do
      stub_const("ExpoPushClient::MAX_MESSAGES", 2)
      3.times { register_device(build_user) }

      PushNotifier.broadcast(title: "New season", body: "It's on")

      batches = enqueued_jobs.select { it["job_class"] == "MobilePushDeliveryJob" }.map { it["arguments"].first }
      expect(batches.map(&:size)).to contain_exactly(2, 1)
      expect(batches.flatten).to match_array(DeviceToken.ids)
    end
  end
end
