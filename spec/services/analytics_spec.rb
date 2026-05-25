# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics do
  let(:user) do
    User.create!(
      first_name: "Analytics",
      last_name: "Tester",
      email: "analytics-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  describe ".track" do
    it "creates an AnalyticsEvent record" do
      expect {
        described_class.track(user: user, event: "test_event", properties: { foo: "bar" })
      }.to change { AnalyticsEvent.count }.by(1)

      event = AnalyticsEvent.last
      expect(event.user).to eq(user)
      expect(event.event_name).to eq("test_event")
      expect(event.properties).to eq("foo" => "bar")
    end

    it "does not raise when PostHog is not configured" do
      expect {
        described_class.track(user: user, event: "safe_event")
      }.not_to raise_error
    end

    it "stores properties as JSONB" do
      described_class.track(
        user: user,
        event: "workout_import_completed",
        properties: { provider: "strava", imported_count: 5, requested_count: 10 }
      )

      event = AnalyticsEvent.last
      expect(event.properties["provider"]).to eq("strava")
      expect(event.properties["imported_count"]).to eq(5)
    end

    it "does not blow up if the DB write fails" do
      allow(AnalyticsEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.track(user: user, event: "failing_event")
      }.not_to raise_error
    end
  end

  describe ".identify" do
    it "does not raise when PostHog is not configured" do
      expect {
        described_class.identify(user: user)
      }.not_to raise_error
    end
  end
end
