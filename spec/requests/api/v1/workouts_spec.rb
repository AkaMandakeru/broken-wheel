# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 workouts", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  path "/api/v1/workouts" do
    get "The player's workouts, newest first" do
      tags "Workouts"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/cursor"
      parameter "$ref" => "#/components/parameters/limit"

      response "200", "a page of workouts" do
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: WorkoutsSchemas::WORKOUT },
          meta: {
            type: :object,
            required: [ "next_cursor" ],
            properties: {
              next_cursor: { type: :string, nullable: true },
              workout_count: { type: :integer, description: "First page only" },
              unique_days: { type: :integer, description: "First page only" }
            }
          }
        }

        before do
          build_workout(user, date: Date.new(2026, 5, 1), km: 5, minutes: 25, hour: 7, minute: 30)
          build_workout(user, date: Date.new(2026, 5, 3), km: 10, minutes: 50)
          build_workout(user, date: Date.new(2026, 5, 3), km: 3, minutes: 20, known_time: false)
          build_workout(build_user, date: Date.new(2026, 5, 4))
        end

        run_test! do
          expect(json_data.pluck("distance_km")).to eq([ 3.0, 10.0, 5.0 ])
          expect(json_body["meta"]).to include("workout_count" => 3, "unique_days" => 2)

          oldest = json_data.last
          expect(oldest).to include("sport" => "run", "workout_date" => "2026-05-01", "start_time" => "07:30",
                                    "start_time_known" => true, "provider" => "manual", "pace_seconds_per_km" => 300)
          expect(oldest["duration"]).to eq("minutes" => 25, "moving_seconds" => 1500, "elapsed_seconds" => 1500)
          expect(json_data.first).to include("start_time" => nil, "start_time_known" => false)
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end

      response "403", "workouts are switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.create!(key: "workouts", enabled: false) }

        run_test! { expect(json_error_code).to eq("feature_disabled") }
      end
    end

    post "Log a workout by hand" do
      tags "Workouts"
      description "XP is credited in the background: when `meta.xp_pending` is true, refetch the season in a few seconds."
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: WorkoutsSchemas::WORKOUT_INPUT

      let(:body) do
        { workout: { sport: "run", workout_date: "2026-05-10", start_time: "06:45", distance_km: 10.5, duration_seconds: 3150 } }
      end

      response "201", "workout created" do
        schema type: :object, required: %w[data meta], properties: {
          data: WorkoutsSchemas::WORKOUT,
          meta: { type: :object, required: [ "xp_pending" ], properties: { xp_pending: { type: :boolean } } }
        }

        before { build_season }

        run_test! do
          expect(json_body["meta"]).to eq("xp_pending" => true)
          expect(json_data).to include("sport" => "run", "distance_km" => 10.5, "start_time" => "06:45",
                                       "start_time_known" => true, "provider" => "manual", "pace_seconds_per_km" => 300)
          expect(json_data["duration"]).to eq("minutes" => 53, "moving_seconds" => 3150, "elapsed_seconds" => 3150)

          workout = user.workouts.sole
          expect(workout.started_at_local).to eq(Time.utc(2026, 5, 10, 6, 45))
          expect(workout.start_minute_of_day).to eq(405)
        end
      end

      response "422", "invalid workout" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { workout: { sport: "yoga", workout_date: "", start_time: "25:00", duration_seconds: 0 } } }

        run_test! do
          expect(json_error_code).to eq("validation_failed")
          expect(json_body.dig("error", "fields").keys).to contain_exactly("sport", "workout_date", "start_time", "duration_seconds")
          expect(user.workouts).to be_empty
        end
      end

      response "400", "no workout in the body" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { workout: "run" } }

        run_test! { expect(json_error_code).to eq("bad_request") }
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  it "pages through workouts with the cursor, with totals on the first page only" do
    3.times { |i| build_workout(user, date: Date.new(2026, 5, 1) + i) }

    get "/api/v1/workouts", params: { limit: 2 }, headers: api_headers(user)
    expect(json_data.pluck("workout_date")).to eq(%w[2026-05-03 2026-05-02])
    cursor = json_body.dig("meta", "next_cursor")

    get "/api/v1/workouts", params: { limit: 2, cursor: cursor }, headers: api_headers(user)
    expect(json_data.pluck("workout_date")).to eq(%w[2026-05-01])
    expect(json_body["meta"]).to eq("next_cursor" => nil)
  end

  it "says XP is not pending when no season is running" do
    post "/api/v1/workouts", headers: api_headers(user), as: :json,
                             params: { workout: { sport: "bike", workout_date: "2026-05-10", duration_seconds: 600 } }

    expect(response).to have_http_status(:created)
    expect(json_body["meta"]).to eq("xp_pending" => false)
    expect(json_data).to include("start_time" => nil, "start_time_known" => false)
  end

  it "runs the same side effects as the web form" do
    challenge = build_challenge(key: "may_miles", sport: "run", requirements: [ { metric: "distance_km", target: 20 } ],
                                starts_at: Date.new(2026, 5, 1), ends_at: Date.new(2026, 5, 31))
    participation = ChallengeParticipation.create!(user: user, challenge: challenge)
    expect(RecomputeChallengeProgress).to receive(:new).with(participation).and_call_original

    expect {
      post "/api/v1/workouts", headers: api_headers(user), as: :json,
                               params: { workout: { sport: "run", workout_date: "2026-05-10", distance_km: 5, duration_seconds: 1800 } }
    }.to change { AnalyticsEvent.where(event_name: "workout_created_manually").count }.by(1)
  end

  it "translates validation messages" do
    post "/api/v1/workouts", headers: api_headers(user, "Accept-Language" => "pt-BR"), as: :json,
                             params: { workout: { sport: "yoga", workout_date: "2026-05-10", duration_seconds: 60 } }

    expect(json_body.dig("error", "fields", "sport")).to eq([ "Esporte deve ser um destes: run, bike, soccer" ])
  end

  describe "Idempotency-Key" do
    let(:headers) { api_headers(user, "Idempotency-Key" => "workout-#{SecureRandom.uuid}") }
    let(:params) { { workout: { sport: "run", workout_date: "2026-05-10", distance_km: 5, duration_seconds: 1500 } } }

    it "creates the workout once and replays the first response to a retry" do
      post "/api/v1/workouts", headers: headers, params: params, as: :json
      first = response.body
      expect(response).to have_http_status(:created)

      expect {
        post "/api/v1/workouts", headers: headers, params: params, as: :json
      }.not_to change(Workout, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(JSON.parse(response.body)).to eq(JSON.parse(first))
      expect(user.workouts.count).to eq(1)
    end

    it "refuses the same key with a different body" do
      post "/api/v1/workouts", headers: headers, params: params, as: :json

      expect {
        post "/api/v1/workouts", headers: headers, as: :json,
                                 params: params.deep_merge(workout: { distance_km: 6 })
      }.not_to change(Workout, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_error_code).to eq("idempotency_key_reused")
    end
  end
end
