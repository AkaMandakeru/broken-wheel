# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workouts", type: :request do
  let(:user) do
    User.create!(
      first_name: "Work",
      last_name: "Tester",
      email: "work-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  describe "GET /workouts" do
    it "redirects to sign in when unauthenticated" do
      get workouts_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders successfully when authenticated" do
      sign_in user
      get workouts_path
      expect(response).to have_http_status(:ok)
    end

    it "shows workouts and stats" do
      user.workouts.create!(sport: "run", distance_km: 5, duration_minutes: 30, workout_date: Date.current, provider: "manual")
      sign_in user
      get workouts_path

      expect(response.body).to include("5.0")
      expect(response.body).to include("30")
    end

    it "shows Browse Strava button when connected" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user
      get workouts_path

      expect(response.body).to include(I18n.t("workouts.index.browse_strava"))
    end

    it "hides Browse Strava button when not connected" do
      sign_in user
      get workouts_path

      expect(response.body).not_to include(I18n.t("workouts.index.browse_strava"))
    end

    it "shows the source badge for strava workouts" do
      user.workouts.create!(sport: "run", distance_km: 10, duration_minutes: 50, workout_date: Date.current, provider: "strava", external_id: "111")
      sign_in user
      get workouts_path

      expect(response.body).to include("Strava")
    end

    it "shows the source badge for manual workouts" do
      user.workouts.create!(sport: "run", distance_km: 5, duration_minutes: 25, workout_date: Date.current, provider: "manual")
      sign_in user
      get workouts_path

      expect(response.body).to include("Manual")
    end
  end

  describe "POST /workouts" do
    it "creates a manual workout" do
      sign_in user

      expect {
        post workouts_path, params: {
          workout: {
            sport: "run",
            distance_km_input: "10",
            distance_m_input: "0",
            duration_hours_input: "0",
            duration_minutes_input: "50",
            duration_seconds_input: "0",
            workout_date: Date.current.to_s
          }
        }
      }.to change { user.workouts.count }.by(1)

      expect(response).to redirect_to(workouts_path)
      workout = user.workouts.last
      expect(workout.provider).to eq("manual")
      expect(workout.sport).to eq("run")
      expect(workout.distance_km).to eq(10.0)
    end
  end

  describe "GET /workouts/strava_activities" do
    it "redirects when not connected to Strava" do
      sign_in user
      get strava_activities_workouts_path

      expect(response).to redirect_to(workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.strava_not_connected"))
    end

    it "renders activities from Strava" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      activities = [
        double(id: 1, sport_type: "Run", name: "Morning Run", distance: 5000.0,
               moving_time: 1800, start_date_local: Time.zone.now, start_date: Time.zone.now)
      ]

      service = instance_double(StravaService)
      allow(StravaService).to receive(:new).and_return(service)
      allow(service).to receive(:activities).and_return(activities)

      get strava_activities_workouts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Morning Run")
      expect(response.body).to include("5.0")
    end

    it "redirects with error on AuthError" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      allow(StravaService).to receive(:new).and_raise(StravaService::AuthError, "bad")

      get strava_activities_workouts_path

      expect(response).to redirect_to(workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.strava_auth_failed"))
    end

    it "redirects with error on RateLimitError" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      allow(StravaService).to receive(:new).and_raise(StravaService::RateLimitError, "slow down")

      get strava_activities_workouts_path

      expect(response).to redirect_to(workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.strava_rate_limited"))
    end

    it "marks already-imported activities" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      user.workouts.create!(sport: "run", distance_km: 5, duration_minutes: 30,
                            workout_date: Date.current, provider: "strava", external_id: "1")
      sign_in user

      activities = [
        double(id: 1, sport_type: "Run", name: "Already Here", distance: 5000.0,
               moving_time: 1800, start_date_local: Time.zone.now, start_date: Time.zone.now)
      ]

      service = instance_double(StravaService)
      allow(StravaService).to receive(:new).and_return(service)
      allow(service).to receive(:activities).and_return(activities)

      get strava_activities_workouts_path

      expect(response.body).to include(I18n.t("workouts.strava_activities.already_imported"))
    end
  end

  describe "POST /workouts/import_strava" do
    it "redirects when not connected" do
      sign_in user
      post import_strava_workouts_path, params: { activity_ids: ["1"] }

      expect(response).to redirect_to(workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.strava_not_connected"))
    end

    it "redirects when no activities selected" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      service = instance_double(StravaService)
      allow(StravaService).to receive(:new).and_return(service)

      post import_strava_workouts_path, params: { activity_ids: [] }

      expect(response).to redirect_to(strava_activities_workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.no_activities_selected"))
    end

    it "imports selected activities as workouts" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      activity = double(
        id: 42, sport_type: "Run", distance: 10_000.0, moving_time: 3000,
        start_date_local: Time.zone.parse("2026-05-10T08:00:00"),
        start_date: Time.zone.parse("2026-05-10T11:00:00"),
        to_h: { "id" => 42, "sport_type" => "Run" }
      )

      service = instance_double(StravaService)
      allow(StravaService).to receive(:new).and_return(service)
      allow(service).to receive(:activity).with("42").and_return(activity)

      expect {
        post import_strava_workouts_path, params: { activity_ids: ["42"] }
      }.to change { user.workouts.count }.by(1)

      expect(response).to redirect_to(workouts_path)
      expect(flash[:notice]).to include("1")

      workout = user.workouts.find_by(external_id: "42")
      expect(workout.provider).to eq("strava")
      expect(workout.sport).to eq("run")
      expect(workout.distance_km).to eq(10.0)
    end

    it "handles AuthError gracefully" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      sign_in user

      allow(StravaService).to receive(:new).and_raise(StravaService::AuthError, "expired")

      post import_strava_workouts_path, params: { activity_ids: ["1"] }

      expect(response).to redirect_to(workouts_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.workouts.strava_auth_failed"))
    end
  end
end
