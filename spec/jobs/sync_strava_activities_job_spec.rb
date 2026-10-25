# frozen_string_literal: true

require "rails_helper"
require "active_job/continuation/test_helper"

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
    result = Strava::ActivityImporter::Result.new(imported: 0, skipped: 0)
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
    result = Strava::ActivityImporter::Result.new(imported: 0, skipped: 0)
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

  describe "as a continuation" do
    include ActiveJob::Continuation::TestHelper

    let(:client) { instance_double(StravaService) }
    let(:pages) { { 1 => [ activity(1) ], 2 => [ activity(2) ], 3 => [] } }
    let(:requested_pages) { [] }

    def activity(id)
      double("Activity", id: id, sport_type: "Run", distance: 5000.0, moving_time: 1500,
                         start_date_local: Time.zone.parse("2026-05-0#{id}T08:00:00"),
                         start_date: Time.zone.parse("2026-05-0#{id}T11:00:00"), to_h: { "id" => id })
    end

    before do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      stub_const("Strava::ActivityImporter::PAGE_SIZE", 1)
      allow(StravaService).to receive(:new).and_return(client)
      allow(client).to receive(:activities_page) do |page:, **|
        requested_pages << page
        pages.fetch(page)
      end
    end

    it "picks up at the page it reached when the worker stops mid-import" do
      described_class.perform_later(user.id)

      interrupt_job_during_step(described_class, :import, cursor: 2) { perform_enqueued_jobs }

      expect(user.workouts.pluck(:external_id)).to eq([ "1" ])
      resumed = enqueued_jobs.sole
      expect(resumed.dig("continuation", "current")).to eq([ "import", 2 ])

      perform_enqueued_jobs

      expect(requested_pages).to eq([ 1, 2, 3 ])
      expect(user.workouts.pluck(:external_id)).to contain_exactly("1", "2")
    end

    it "keeps its place when Strava rate-limits it, and waits before retrying" do
      limited = false
      allow(client).to receive(:activities_page) do |page:, **|
        if page == 2 && !limited
          limited = true
          raise StravaService::RateLimitError, "slow down"
        end

        requested_pages << page
        pages.fetch(page)
      end

      described_class.perform_later(user.id)
      perform_enqueued_jobs

      retry_job = enqueued_jobs.sole
      expect(retry_job.dig("continuation", "current")).to eq([ "import", 2 ])
      expect(Time.zone.parse(retry_job["scheduled_at"].to_s)).to be > 10.minutes.from_now

      perform_enqueued_jobs(at: 1.hour.from_now)

      expect(requested_pages).to eq([ 1, 2, 3 ])
      expect(user.workouts.pluck(:external_id)).to contain_exactly("1", "2")
    end
  end
end
