# frozen_string_literal: true

require "rails_helper"

RSpec.describe StravaService do
  let(:user) do
    User.create!(
      first_name: "Svc",
      last_name: "Tester",
      email: "svc-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  let(:token) do
    user.create_strava_token!(
      access_token: "access-1",
      refresh_token: "refresh-1",
      expires_at: 1.hour.from_now.to_i
    )
  end

  before { token }

  def strava_fault(status, message)
    Strava::Errors::Fault.new(
      nil,
      { status: status, body: { "message" => message } }
    )
  end

  describe "#initialize" do
    it "raises AuthError when user has no token" do
      user.strava_token&.destroy
      expect { described_class.new(user.reload) }.to raise_error(StravaService::AuthError)
    end

    it "refreshes the token automatically when expired" do
      token.update!(expires_at: 1.hour.ago.to_i)

      token_response = double(
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_at: Time.at(2.hours.from_now.to_i)
      )

      oauth_client = instance_double(Strava::OAuth::Client)
      allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:oauth_token).with(
        grant_type: "refresh_token",
        refresh_token: "refresh-1"
      ).and_return(token_response)

      described_class.new(user.reload)

      expect(token.reload.access_token).to eq("new-access")
      expect(token.refresh_token).to eq("new-refresh")
    end

    it "preserves existing refresh_token when response has nil refresh_token" do
      token.update!(expires_at: 1.hour.ago.to_i)

      token_response = double(
        access_token: "new-access",
        refresh_token: nil,
        expires_at: Time.at(2.hours.from_now.to_i)
      )

      oauth_client = instance_double(Strava::OAuth::Client)
      allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:oauth_token).and_return(token_response)

      described_class.new(user.reload)

      expect(token.reload.refresh_token).to eq("refresh-1")
    end

    it "raises AuthError when refresh fails" do
      token.update!(expires_at: 1.hour.ago.to_i)

      oauth_client = instance_double(Strava::OAuth::Client)
      allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
      allow(oauth_client).to receive(:oauth_token).and_raise(strava_fault(401, "Authorization Error"))

      expect { described_class.new(user.reload) }.to raise_error(StravaService::AuthError)
    end

    it "does not refresh when token is still valid" do
      expect(Strava::OAuth::Client).not_to receive(:new)
      described_class.new(user)
    end
  end

  describe "#athlete" do
    it "returns the athlete from the API client" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)

      athlete = double(id: 123, firstname: "Test")
      allow(api_client).to receive(:athlete).and_return(athlete)

      service = described_class.new(user)
      expect(service.athlete).to eq(athlete)
    end

    it "raises AuthError on 401 fault" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:athlete).and_raise(strava_fault(401, "Unauthorized"))

      service = described_class.new(user)
      expect { service.athlete }.to raise_error(StravaService::AuthError)
    end
  end

  describe "#activities" do
    it "delegates to the API client with pagination block" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)

      activities = [double(id: 1), double(id: 2)]
      allow(api_client).to receive(:athlete_activities) do |_opts, &block|
        activities.each(&block) if block
        activities
      end

      service = described_class.new(user)
      collected = []
      service.activities(page_size: 50) { |a| collected << a }
      expect(collected.map(&:id)).to eq([1, 2])
    end

    it "passes after parameter when provided" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)

      expect(api_client).to receive(:athlete_activities)
        .with(hash_including(after: 1000))
        .and_return([])

      described_class.new(user).activities(after: 1000)
    end

    it "raises RateLimitError on 429 fault" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:athlete_activities).and_raise(strava_fault(429, "Rate Limit Exceeded"))

      service = described_class.new(user)
      expect { service.activities }.to raise_error(StravaService::RateLimitError)
    end

    it "raises Error on 5xx fault" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:athlete_activities).and_raise(strava_fault(500, "Internal Server Error"))

      service = described_class.new(user)
      expect { service.activities }.to raise_error(StravaService::Error)
    end
  end

  describe "#activity" do
    it "fetches a single activity by ID" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)

      activity = double(id: 42, sport_type: "Run")
      expect(api_client).to receive(:activity).with(42).and_return(activity)

      service = described_class.new(user)
      expect(service.activity(42)).to eq(activity)
    end

    it "raises AuthError on 403 fault" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:activity).and_raise(strava_fault(403, "Forbidden"))

      service = described_class.new(user)
      expect { service.activity(1) }.to raise_error(StravaService::AuthError)
    end

    it "raises RateLimitError on 429 fault" do
      api_client = instance_double(Strava::Api::Client)
      allow(Strava::Api::Client).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:activity).and_raise(strava_fault(429, "Rate Limit Exceeded"))

      service = described_class.new(user)
      expect { service.activity(1) }.to raise_error(StravaService::RateLimitError)
    end
  end
end
