# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "#connected_to_strava?", type: :model do
  let(:user) do
    User.create!(
      first_name: "Conn",
      last_name: "Tester",
      email: "conn-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  it "is false when no token is associated" do
    expect(user.connected_to_strava?).to be false
  end

  it "is true even when the access token is expired, as long as a refresh token exists" do
    user.create_strava_token!(
      access_token: "expired",
      refresh_token: "still-good",
      expires_at: 1.hour.ago.to_i
    )
    expect(user.connected_to_strava?).to be true
  end

  it "is false when refresh_token is missing" do
    token = user.build_strava_token(access_token: "a", refresh_token: nil, expires_at: 1.hour.from_now.to_i)
    expect(token.valid?).to be false
    expect(user.connected_to_strava?).to be false
  end
end
