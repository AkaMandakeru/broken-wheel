# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strava::ActivityImporter do
  let(:user) do
    User.create!(
      first_name: "Imp",
      last_name: "Tester",
      email: "imp-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  let(:client) { instance_double(StravaService) }

  def strava_activity(attrs = {})
    defaults = {
      id: 12345,
      sport_type: "Run",
      distance: 5000.0,
      moving_time: 1800,
      start_date_local: Time.zone.parse("2026-05-10T08:00:00"),
      start_date: Time.zone.parse("2026-05-10T11:00:00")
    }
    merged = defaults.merge(attrs)
    double("Activity", **merged, to_h: merged.stringify_keys)
  end

  def run_import(activity)
    allow(client).to receive(:activities).and_yield(activity)
    described_class.new(user, client: client).call
  end

  def run_import_one(activity)
    described_class.new(user, client: client).import_one(activity)
  end

  describe "#call" do
    it "creates a workout from a Run activity" do
      result = run_import(strava_activity)

      workout = user.workouts.find_by(provider: "strava", external_id: "12345")
      expect(workout).to be_present
      expect(workout.sport).to eq("run")
      expect(workout.distance_km).to eq(5.0)
      expect(workout.duration_minutes).to eq(30)
      expect(workout.workout_date).to eq(Date.new(2026, 5, 10))
      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(0)
    end

    it "maps TrailRun to run" do
      run_import(strava_activity(id: 1, sport_type: "TrailRun"))
      expect(user.workouts.find_by(external_id: "1").sport).to eq("run")
    end

    it "maps Ride to bike" do
      run_import(strava_activity(id: 2, sport_type: "Ride"))
      expect(user.workouts.find_by(external_id: "2").sport).to eq("bike")
    end

    it "maps MountainBikeRide to bike" do
      run_import(strava_activity(id: 3, sport_type: "MountainBikeRide"))
      expect(user.workouts.find_by(external_id: "3").sport).to eq("bike")
    end

    it "maps Soccer to soccer" do
      run_import(strava_activity(id: 4, sport_type: "Soccer"))
      expect(user.workouts.find_by(external_id: "4").sport).to eq("soccer")
    end

    it "is idempotent across reruns" do
      activity = strava_activity(id: 99, sport_type: "Ride", distance: 10_000.0, moving_time: 1200)
      run_import(activity)
      expect { run_import(activity) }.not_to change { user.workouts.count }
    end

    it "skips activities with an unmapped sport type" do
      result = run_import(strava_activity(id: 7, sport_type: "AlpineSki"))
      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
      expect(user.workouts.count).to eq(0)
    end

    it "updates an existing strava workout when the activity changes" do
      run_import(strava_activity(id: 555, distance: 3000.0, moving_time: 1200))
      run_import(strava_activity(id: 555, distance: 4000.0, moving_time: 1500))

      workout = user.workouts.find_by(provider: "strava", external_id: "555")
      expect(workout.distance_km).to eq(4.0)
      expect(workout.duration_minutes).to eq(25)
    end

    it "returns achievements in the result" do
      result = run_import(strava_activity)
      expect(result.achievements).to be_an(Array)
    end

    it "handles zero moving_time gracefully" do
      run_import(strava_activity(id: 800, moving_time: 0))
      expect(user.workouts.find_by(external_id: "800").duration_minutes).to eq(0)
    end

    it "falls back to Date.current when dates are nil" do
      run_import(strava_activity(id: 900, start_date_local: nil, start_date: nil))
      expect(user.workouts.find_by(external_id: "900").workout_date).to eq(Date.current)
    end
  end

  describe "#import_one" do
    it "imports a single activity and returns true" do
      expect(run_import_one(strava_activity(id: 42))).to be true
      expect(user.workouts.find_by(external_id: "42")).to be_present
    end

    it "returns false for an unmapped sport" do
      expect(run_import_one(strava_activity(id: 43, sport_type: "Yoga"))).to be false
      expect(user.workouts.count).to eq(0)
    end

    it "runs the achievement checker" do
      expect(AchievementChecker).to receive(:new).with(user).and_call_original
      run_import_one(strava_activity(id: 50))
    end
  end

  describe "auto-assign challenge" do
    let!(:challenge) do
      Challenge.create!(
        title: "Run 10km",
        description: "Weekly run",
        challenge_type: "weekly",
        sport: "run",
        target_value: 10,
        target_unit: "km",
        starts_at: Date.current.beginning_of_week(:monday),
        ends_at: Date.current.end_of_week(:monday),
        status: "active"
      )
    end

    let!(:participation) do
      ChallengeParticipation.create!(challenge: challenge, user: user, progress_value: 0)
    end

    it "auto-assigns workout to a matching active challenge participation" do
      run_import(strava_activity(id: 200, sport_type: "Run", distance: 5000.0))
      workout = user.workouts.find_by(external_id: "200")
      expect(workout.challenge_participation).to eq(participation)
    end

    it "does not assign to a completed participation" do
      participation.update!(completed_at: Time.current)
      run_import(strava_activity(id: 201, sport_type: "Run"))
      workout = user.workouts.find_by(external_id: "201")
      expect(workout.challenge_participation).to be_nil
    end

    it "does not assign when sport does not match" do
      run_import(strava_activity(id: 202, sport_type: "Ride"))
      workout = user.workouts.find_by(external_id: "202")
      expect(workout.challenge_participation).to be_nil
    end

    it "recomputes challenge progress after import" do
      run_import(strava_activity(id: 203, sport_type: "Run", distance: 5000.0))
      expect(participation.reload.progress_value.to_f).to eq(5.0)
    end
  end
end
