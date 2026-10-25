# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobilePushDeliveryJob do
  include ActiveJob::TestHelper

  let(:user) { build_user }
  let!(:alive) { DeviceToken.create!(user: user, platform: "expo", token: "ExponentPushToken[alive]") }
  let!(:gone) { DeviceToken.create!(user: user, platform: "expo", token: "ExponentPushToken[gone]") }
  let(:client) { instance_double(ExpoPushClient) }
  let(:payload) { { title: "Level up", body: "Level 3", path: "/seasons/1", tag: "level" } }

  before { allow(ExpoPushClient).to receive(:new).and_return(client) }

  it "sends one message per device, drops unregistered ones and checks the receipts later" do
    allow(client).to receive(:send_messages).and_return([
      { "status" => "ok", "id" => "receipt-1" },
      { "status" => "error", "message" => "not registered", "details" => { "error" => "DeviceNotRegistered" } }
    ])

    described_class.perform_now([ alive.id, gone.id ], payload)

    expect(client).to have_received(:send_messages).with([
      { to: alive.token, title: "Level up", body: "Level 3", data: { path: "/seasons/1", tag: "level" }, sound: "default" },
      { to: gone.token, title: "Level up", body: "Level 3", data: { path: "/seasons/1", tag: "level" }, sound: "default" }
    ])
    expect(DeviceToken.exists?(gone.id)).to be(false)
    expect(DeviceToken.exists?(alive.id)).to be(true)
    expect(ExpoPushReceiptsJob).to have_been_enqueued.with({ "receipt-1" => alive.id })
  end

  it "keeps a device whose ticket failed for another reason" do
    allow(client).to receive(:send_messages).and_return([
      { "status" => "error", "message" => "too big", "details" => { "error" => "MessageTooBig" } },
      { "status" => "error", "message" => "too big", "details" => { "error" => "MessageTooBig" } }
    ])

    described_class.perform_now([ alive.id, gone.id ], payload)

    expect(DeviceToken.count).to eq(2)
    expect(ExpoPushReceiptsJob).not_to have_been_enqueued
  end

  it "retries when Expo is rate limiting or down" do
    allow(client).to receive(:send_messages).and_raise(ExpoPushClient::Unavailable, "Expo send: 429")

    described_class.perform_now([ alive.id ], payload)

    expect(described_class).to have_been_enqueued.with([ alive.id ], payload)
  end

  it "gives up quietly when Expo rejects the request" do
    allow(client).to receive(:send_messages).and_raise(ExpoPushClient::Error, "Expo send: 401")

    expect { described_class.perform_now([ alive.id ], payload) }.not_to raise_error
    expect(described_class).not_to have_been_enqueued
  end

  it "does nothing when the devices are gone" do
    described_class.perform_now([ 0 ], payload)

    expect(ExpoPushClient).not_to have_received(:new)
  end
end
