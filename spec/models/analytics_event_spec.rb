# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsEvent, type: :model do
  let(:user) do
    User.create!(
      first_name: "Event",
      last_name: "Tester",
      email: "event-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  it "creates a valid event with user and properties" do
    event = described_class.create!(
      user: user,
      event_name: "test_event",
      properties: { key: "value" }
    )

    expect(event).to be_persisted
    expect(event.user).to eq(user)
    expect(event.event_name).to eq("test_event")
    expect(event.properties).to eq("key" => "value")
  end

  it "allows nil user for anonymous events" do
    event = described_class.create!(event_name: "anonymous_event")
    expect(event).to be_persisted
    expect(event.user).to be_nil
  end

  it "defaults properties to empty hash" do
    event = described_class.create!(user: user, event_name: "bare_event")
    expect(event.properties).to eq({})
  end
end
