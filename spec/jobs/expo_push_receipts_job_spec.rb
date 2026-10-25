# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpoPushReceiptsJob do
  let(:user) { build_user }
  let!(:alive) { DeviceToken.create!(user: user, platform: "expo", token: "ExponentPushToken[alive]") }
  let!(:gone) { DeviceToken.create!(user: user, platform: "expo", token: "ExponentPushToken[gone]") }
  let(:client) { instance_double(ExpoPushClient) }

  before { allow(ExpoPushClient).to receive(:new).and_return(client) }

  it "deletes the devices whose receipts say they are no longer registered" do
    allow(client).to receive(:receipts).with(%w[r-alive r-gone]).and_return(
      "r-alive" => { "status" => "ok" },
      "r-gone" => { "status" => "error", "details" => { "error" => "DeviceNotRegistered" } }
    )

    described_class.perform_now({ "r-alive" => alive.id, "r-gone" => gone.id })

    expect(DeviceToken.pluck(:id)).to eq([ alive.id ])
  end
end
