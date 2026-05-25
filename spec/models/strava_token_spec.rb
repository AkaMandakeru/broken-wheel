# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaToken, type: :model do
  let(:user) do
    User.create!(
      first_name: "Strava",
      last_name: "Tester",
      email: "strava-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def build_token(expires_at:)
    user.build_strava_token(
      access_token: "access-#{SecureRandom.hex(4)}",
      refresh_token: "refresh-#{SecureRandom.hex(4)}",
      expires_at: expires_at
    )
  end

  describe "#expired?" do
    it "is true when expires_at is nil" do
      token = build_token(expires_at: nil)
      expect(token.expired?).to be true
    end

    it "is true when expires_at is in the past" do
      token = build_token(expires_at: 1.hour.ago.to_i)
      expect(token.expired?).to be true
    end

    it "is true when expires_at is within the leeway window" do
      token = build_token(expires_at: 30.seconds.from_now.to_i)
      expect(token.expired?).to be true
    end

    it "is false when expires_at is comfortably in the future" do
      token = build_token(expires_at: 1.hour.from_now.to_i)
      expect(token.expired?).to be false
    end
  end

  describe "token encryption" do
    it "stores access_token encrypted at rest" do
      token = build_token(expires_at: 1.hour.from_now.to_i)
      token.access_token = "plaintext-access-value"
      token.save!

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT access_token FROM strava_tokens WHERE id = #{token.id}"
      )
      expect(raw).not_to include("plaintext-access-value")
      expect(token.reload.access_token).to eq("plaintext-access-value")
    end
  end
end
