# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounts::Registration do
  let(:attributes) do
    { first_name: "Ana", last_name: "Lima", email: "ana@example.com", password: "secret123",
      password_confirmation: "secret123" }
  end

  before { allow(SlackNotifier).to receive(:notify) }

  describe ".call" do
    it "tells Slack where the signup came from" do
      user = described_class.call(attributes, source: "App · android · v1.2.0")

      expect(user).to be_persisted
      expect(SlackNotifier).to have_received(:notify)
        .with(:user_registered, user: user, extra: { "Source" => "App · android · v1.2.0" })
    end

    it "announces nothing when the user is invalid" do
      user = described_class.call(attributes.merge(email: "bad"), source: described_class::WEB)

      expect(user).not_to be_persisted
      expect(SlackNotifier).not_to have_received(:notify)
    end
  end

  describe ".app_source" do
    it "is just App when the client says nothing about itself" do
      expect(described_class.app_source).to eq("App")
    end

    it "adds the platform and version when known" do
      expect(described_class.app_source(platform: "ios", app_version: "1.0.0")).to eq("App · ios · v1.0.0")
      expect(described_class.app_source(app_version: "1.0.0")).to eq("App · v1.0.0")
    end
  end
end
