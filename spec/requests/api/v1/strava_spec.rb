# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 Strava", type: :request do
  include ActiveJob::TestHelper

  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  def connect_strava(for_user = user)
    for_user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i, athlete_id: 999)
  end

  def strava_activity(id:, sport_type: "Run", name: "Morning Run")
    double("Activity", id: id, sport_type: sport_type, name: name, distance: 10_000.0, moving_time: 3000,
                       elapsed_time: 3100, start_date_local: Time.utc(2026, 5, 10, 8),
                       start_date: Time.utc(2026, 5, 10, 11), to_h: { "id" => id, "sport_type" => sport_type })
  end

  def stub_strava_service
    instance_double(StravaService).tap { |service| allow(StravaService).to receive(:new).and_return(service) }
  end

  error_schema = { "$ref" => "#/components/schemas/error" }

  path "/api/v1/strava/authorize" do
    post "Start linking Strava" do
      tags "Strava"
      description "Open `authorize_url` with an auth session. Strava redirects to the app with `code`, `scope` " \
                  "and `state`; post them to /api/v1/strava/callback within 10 minutes."
      produces "application/json"

      response "200", "where to send the player" do
        schema type: :object, required: [ "data" ], properties: {
          data: { type: :object, required: %w[authorize_url state],
                  properties: { authorize_url: { type: :string }, state: { type: :string } } }
        }

        run_test! do
          url = URI.parse(json_data["authorize_url"])
          query = Rack::Utils.parse_query(url.query)
          expect("#{url.scheme}://#{url.host}#{url.path}").to eq("https://www.strava.com/oauth/mobile/authorize")
          expect(query).to include("client_id" => ENV.fetch("STRAVA_CLIENT_ID"), "response_type" => "code",
                                   "approval_prompt" => "auto", "scope" => "read,activity:read_all",
                                   "redirect_uri" => "http://www.example.com/auth/strava/callback",
                                   "state" => json_data["state"])
          expect(Strava::Connection.valid_state?(user, json_data["state"])).to be(true)
        end
      end

      response "401", "not signed in" do
        schema error_schema
        let(:Authorization) { nil }

        run_test!
      end

      response "403", "integrations are switched off" do
        schema error_schema
        before { FeatureFlag.create!(key: "integrations", enabled: false) }

        run_test! { expect(json_error_code).to eq("feature_disabled") }
      end
    end
  end

  it "redirects to the app's universal link when one is configured" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("STRAVA_MOBILE_REDIRECT_URI").and_return("https://app.example.com/strava")

    post "/api/v1/strava/authorize", headers: api_headers(user)

    expect(Rack::Utils.parse_query(URI.parse(json_data["authorize_url"]).query)["redirect_uri"]).to eq("https://app.example.com/strava")
  end

  it "expires the state after 10 minutes and binds it to the player" do
    state = Strava::Connection.state_for(user)

    expect(Strava::Connection.valid_state?(build_user, state)).to be(false)
    travel(11.minutes) { expect(Strava::Connection.valid_state?(user, state)).to be(false) }
  end

  path "/api/v1/strava/callback" do
    post "Finish linking Strava" do
      tags "Strava"
      description "Exchanges the code on the server and starts importing the player's Strava history."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[code state],
        properties: { code: { type: :string }, state: { type: :string }, scope: { type: :string },
                      error: { type: :string, description: "What Strava sent instead of a code, if the player declined" } }
      }

      let(:oauth_client) { instance_double(Strava::OAuth::Client) }
      let(:token_response) do
        double(access_token: "strava-access", refresh_token: "strava-refresh",
               expires_at: Time.at(2.hours.from_now.to_i), athlete: double(id: 4242))
      end
      let(:body) { { code: "valid-code", state: Strava::Connection.state_for(user), scope: "read,activity:read_all" } }

      before do
        allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
        allow(oauth_client).to receive(:oauth_token).with(code: "valid-code").and_return(token_response)
      end

      response "200", "linked" do
        schema type: :object, required: [ "data" ], properties: { data: WorkoutsSchemas::INTEGRATION }

        run_test! do
          expect(json_data).to include("provider" => "strava", "connected" => true, "athlete_id" => 4242)
          expect(user.strava_token.reload).to have_attributes(access_token: "strava-access", refresh_token: "strava-refresh",
                                                              scope: "read,activity:read_all")
          expect(SyncStravaActivitiesJob).to have_been_enqueued.with(user.id)
          expect(AnalyticsEvent.where(user: user, event_name: "user_connected_strava")).to exist
        end
      end

      response "422", "state is invalid, expired or someone else's" do
        schema error_schema
        let(:body) { { code: "valid-code", state: Strava::Connection.state_for(build_user) } }

        run_test! do
          expect(json_error_code).to eq("invalid_state")
          expect(user.strava_token).to be_nil
        end
      end

      response "401", "not signed in" do
        schema error_schema
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  it "answers strava_connect_failed when Strava refuses the code" do
    oauth_client = instance_double(Strava::OAuth::Client)
    allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
    allow(oauth_client).to receive(:oauth_token).and_raise(Strava::Errors::Fault.new(nil, { status: 400, body: {} }))

    post "/api/v1/strava/callback", headers: api_headers(user), as: :json,
                                    params: { code: "bad", state: Strava::Connection.state_for(user) }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_error_code).to eq("strava_connect_failed")
    expect(SyncStravaActivitiesJob).not_to have_been_enqueued
  end

  it "answers strava_connect_failed when the player declined on Strava" do
    post "/api/v1/strava/callback", headers: api_headers(user), as: :json,
                                    params: { error: "access_denied", state: Strava::Connection.state_for(user) }

    expect(json_error_code).to eq("strava_connect_failed")
  end

  path "/api/v1/strava/activities" do
    get "Recent Strava activities to pick from" do
      tags "Strava"
      produces "application/json"

      response "200", "the latest activities" do
        schema type: :object, required: [ "data" ], properties: {
          data: { type: :array, items: WorkoutsSchemas::STRAVA_ACTIVITY }
        }

        before do
          connect_strava
          user.workouts.create!(sport: "run", distance_km: 10, duration_minutes: 50, workout_date: Date.new(2026, 5, 10),
                                provider: "strava", external_id: "1")
          service = stub_strava_service
          allow(service).to receive(:activities).with(page_size: 50)
                                                .and_return([ strava_activity(id: 1), strava_activity(id: 2, sport_type: "Yoga", name: "Stretch") ])
        end

        run_test! do
          expect(json_data.first).to include("id" => "1", "name" => "Morning Run", "sport" => "run", "importable" => true,
                                             "imported" => true, "distance_km" => 10.0, "moving_time_seconds" => 3000,
                                             "start_date" => "2026-05-10T11:00:00Z", "start_date_local" => "2026-05-10T08:00:00")
          expect(json_data.second).to include("id" => "2", "sport" => nil, "importable" => false, "imported" => false)
        end
      end

      response "422", "Strava isn't linked" do
        schema error_schema

        run_test! { expect(json_error_code).to eq("strava_not_connected") }
      end

      response "409", "Strava access was revoked: link it again" do
        schema error_schema
        before do
          connect_strava
          allow(StravaService).to receive(:new).and_raise(StravaService::AuthError, "revoked")
        end

        run_test! { expect(json_error_code).to eq("strava_auth_failed") }
      end

      response "429", "Strava's rate limit" do
        schema error_schema
        before do
          connect_strava
          allow(stub_strava_service).to receive(:activities).and_raise(StravaService::RateLimitError, "slow down")
        end

        run_test! { expect(json_error_code).to eq("strava_rate_limited") }
      end

      response "502", "Strava is failing" do
        schema error_schema
        before do
          connect_strava
          allow(stub_strava_service).to receive(:activities).and_raise(StravaService::Error, "HTTP 500")
        end

        run_test! { expect(json_error_code).to eq("strava_unavailable") }
      end

      response "401", "not signed in" do
        schema error_schema
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  path "/api/v1/strava/import" do
    post "Import picked Strava activities" do
      tags "Strava"
      description "Runs in the background. New workouts (and their XP) show up a few seconds later."
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "activity_ids" ],
        properties: { activity_ids: { type: :array, items: { type: :string }, minItems: 1, maxItems: Api::V1::StravaController::MAX_IMPORT } }
      }

      let(:body) { { activity_ids: %w[42 43] } }

      response "202", "import queued" do
        schema type: :object, required: [ "data" ], properties: {
          data: { type: :object, required: [ "requested_count" ], properties: { requested_count: { type: :integer } } }
        }
        before { connect_strava }

        run_test! do
          expect(json_data).to eq("requested_count" => 2)
          expect(ImportStravaActivitiesJob).to have_been_enqueued.with(user.id, %w[42 43])
        end
      end

      response "422", "nothing picked" do
        schema error_schema
        let(:body) { { activity_ids: [] } }
        before { connect_strava }

        run_test! { expect(json_error_code).to eq("no_activities_selected") }
      end

      response "401", "not signed in" do
        schema error_schema
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  it "refuses more activities than one import takes" do
    connect_strava
    ids = (1..(Api::V1::StravaController::MAX_IMPORT + 1)).map(&:to_s)

    post "/api/v1/strava/import", headers: api_headers(user), params: { activity_ids: ids }, as: :json

    expect(json_error_code).to eq("too_many_activities")
    expect(ImportStravaActivitiesJob).not_to have_been_enqueued
  end

  it "queues one import per Idempotency-Key" do
    connect_strava
    headers = api_headers(user, "Idempotency-Key" => SecureRandom.uuid)

    2.times { post "/api/v1/strava/import", headers: headers, params: { activity_ids: [ "42" ] }, as: :json }

    expect(response.headers["Idempotent-Replayed"]).to eq("true")
    expect(ImportStravaActivitiesJob).to have_been_enqueued.exactly(:once)
  end

  it "imports through the same service as the web, with the same events" do
    connect_strava
    service = stub_strava_service
    allow(service).to receive(:activity).with("42").and_return(strava_activity(id: 42))
    expect(SlackNotifier).to receive(:notify).with(:workout_imported, user: user, extra: { "Workouts" => 1, "Source" => "Strava" })

    perform_enqueued_jobs do
      post "/api/v1/strava/import", headers: api_headers(user), params: { activity_ids: [ "42" ] }, as: :json
    end

    expect(user.workouts.sole).to have_attributes(provider: "strava", external_id: "42", sport: "run")
    expect(AnalyticsEvent.where(user: user).pluck(:event_name)).to include("workout_import_started", "workout_import_completed")
  end

  path "/api/v1/strava" do
    delete "Unlink Strava" do
      tags "Strava"

      response "204", "unlinked (also when it wasn't linked)" do
        before { connect_strava }

        run_test! { expect(user.reload.strava_token).to be_nil }
      end

      response "401", "not signed in" do
        schema error_schema
        let(:Authorization) { nil }

        run_test!
      end
    end
  end
end
