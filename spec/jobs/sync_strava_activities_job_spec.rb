# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncStravaActivitiesJob do
  let(:user) do
    User.create!(
      first_name: "Job",
      last_name: "Tester",
      email: "job-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  it "discards when the user is missing" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "does nothing when the user is not connected to Strava" do
    expect(Strava::ActivityImporter).not_to receive(:new)
    described_class.new.perform(user.id)
  end

  it "invokes the importer when the user is connected" do
    user.create_strava_token!(
      access_token: "a",
      refresh_token: "r",
      expires_at: 1.hour.from_now.to_i
    )
    result = Strava::ActivityImporter::Result.new(imported: 0, skipped: 0, achievements: [])
    importer = instance_double(Strava::ActivityImporter, call: result)
    expect(Strava::ActivityImporter).to receive(:new).with(user, after: nil).and_return(importer)

    described_class.new.perform(user.id)
  end

  it "passes the after parameter to the importer" do
    user.create_strava_token!(
      access_token: "a",
      refresh_token: "r",
      expires_at: 1.hour.from_now.to_i
    )
    result = Strava::ActivityImporter::Result.new(imported: 0, skipped: 0, achievements: [])
    importer = instance_double(Strava::ActivityImporter, call: result)
    expect(Strava::ActivityImporter).to receive(:new).with(user, after: 1000).and_return(importer)

    described_class.new.perform(user.id, after: 1000)
  end

  it "swallows AuthError so retries do not run forever" do
    user.create_strava_token!(
      access_token: "a",
      refresh_token: "r",
      expires_at: 1.hour.from_now.to_i
    )
    allow(Strava::ActivityImporter).to receive(:new).and_raise(StravaService::AuthError, "bad token")

    expect { described_class.new.perform(user.id) }.not_to raise_error
  end
end
